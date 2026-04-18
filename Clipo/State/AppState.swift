import AppKit
import Defaults
import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var items: [ClipItem] = []
    var activeFilter: ClipFilter = .history
    var pinboards: [Pinboard] = []
    var selectedID: UUID?
    var searchQuery: String = ""

    /// Ordered IDs of items the user explicitly multi-selected. The order
    /// is click-sequence so that Enter-to-paste emits them in the exact
    /// sequence the user picked them. Empty means single-select mode — UI
    /// treats `selectedID` as the sole "focus" card.
    ///
    /// Every mutation rebuilds `selectionIndexMap` so lookups during
    /// carousel renders stay O(1) — a naive `firstIndex(of:)` per card
    /// per render was O(N×M) on big selections.
    var selectionOrder: [UUID] = [] {
        didSet {
            selectionIndexMap = Dictionary(
                uniqueKeysWithValues: selectionOrder.enumerated().map { ($1, $0 + 1) }
            )
        }
    }
    private var selectionIndexMap: [UUID: Int] = [:]

    /// Convenience: 2+ cards highlighted for a batch action.
    var isMultiSelecting: Bool { selectionOrder.count >= 2 }

    /// O(1) membership check for rendering.
    func isInSelection(_ id: UUID) -> Bool {
        selectionIndexMap[id] != nil
    }

    /// 1-based position in the paste queue; nil when not in selection.
    /// Used to draw the small stack-order chip on each selected card.
    func selectionIndex(of id: UUID) -> Int? {
        selectionIndexMap[id]
    }

    /// True while the user is holding the Option key inside the panel.
    /// Used to show ⌥1–⌥9 quick-paste badges over each card.
    var isOptionDown: Bool = false

    /// True for ~1.8s after a paste-stack attempt with no pastable items
    /// (e.g. selection was only images / colors). FooterHintBar watches
    /// this and swaps in a "No text to paste" message.
    var flashStackError: Bool = false

    /// Cached script list. Loaded once at launch (plus on-demand refresh
    /// from the Scripts settings pane) so the right-click menu doesn't hit
    /// disk on every open.
    var scripts: [ClipoScript] = []

    /// Reflects `AXIsProcessTrusted()` — driven by `recheckAccessibility()`
    /// on every panel open. When false, RootView shows a persistent banner.
    var isAccessibilityGranted: Bool = Accessibility.isTrusted(prompt: false)

    func recheckAccessibility() {
        isAccessibilityGranted = Accessibility.isTrusted(prompt: false)
    }

    /// Top-bar tab order: History, Images, Files, then user-defined Pinboards.
    var topBarFilters: [ClipFilter] {
        var list: [ClipFilter] = [.history, .images, .files]
        for board in pinboards {
            list.append(.pinboard(board.id))
        }
        return list
    }

    func pinboard(for filter: ClipFilter) -> Pinboard? {
        if case let .pinboard(id) = filter {
            return pinboards.first { $0.id == id }
        }
        return nil
    }

    func setFilter(_ filter: ClipFilter) {
        activeFilter = filter
        // Filter tab swap doesn't need a DB round-trip — applyFilter()
        // re-derives the visible items from the already-cached allItems.
        applyFilter()
    }

    func selectFilterByIndex(_ index: Int) {
        let list = topBarFilters
        guard index >= 0, index < list.count else { return }
        setFilter(list[index])
    }

    /// Bumped every time the panel is opened. RootView observes this to reset
    /// focus and scroll position on each re-entry.
    var openToken = UUID()

    weak var appDelegate: AppDelegate?

    private var context: ModelContext { Storage.shared.context }

    /// Unfiltered, already-sorted snapshot of the entire history. We fetch
    /// once per "hard" event (new copy, delete, clear, pinboard move, defaults
    /// change) and then derive `items` from this via applyFilter(). Search
    /// keystrokes and filter-tab swaps re-derive without a DB round-trip.
    private var allItems: [ClipItem] = []

    init() {
        reload()
    }

    // MARK: - History operations

    func add(_ item: ClipItem) {
        // Dedup — if an existing recent item supersedes the new one, bump
        // its lastCopiedAt in place. `allItems` is the same sorted snapshot
        // we'd otherwise fetch, so scan it directly and avoid a SwiftData
        // round-trip on every copy event.
        if let existing = allItems.prefix(50).first(where: { $0.supersedes(item) }) {
            existing.lastCopiedAt = .now
            existing.numberOfCopies += 1
            try? context.save()
            // Promote in-place so the duplicate moves to the front without a
            // full re-fetch (same trick bumpRecency uses after paste).
            if let idx = allItems.firstIndex(where: { $0.id == existing.id }) {
                allItems.remove(at: idx)
            }
            allItems.insert(existing, at: 0)
            applyFilter()
            return
        }

        context.insert(item)
        try? context.save()
        enforceHistoryLimit()
        reload()
        maybeKickOffOCR(for: item)
    }

    /// In-flight OCR results waiting to be written back. A burst of
    /// screenshots used to trigger one context.save() + one applyFilter
    /// per image; we now coalesce via a 200ms debounced drain so a
    /// 10-screenshot spam is one save + one filter pass.
    private var pendingOCRUpdates: [UUID: String] = [:]
    private var ocrDrainTimer: Timer?

    /// Spawns an off-main OCR task for new image items. No-op for anything
    /// else (text, url, files) or when the user disabled OCR. Results are
    /// coalesced through `pendingOCRUpdates` + `ocrDrainTimer` so bursty
    /// screenshot workflows don't thrash SwiftData.
    private func maybeKickOffOCR(for item: ClipItem) {
        guard Defaults[.ocrEnabled] else { return }
        guard item.primaryKind == .image, let data = item.imageData else { return }
        let id = item.id
        let maxPixels = Defaults[.ocrMaxPixels]
        Task.detached(priority: .utility) {
            guard let text = await OCRService.extractText(from: data, maxPixels: maxPixels) else {
                NSLog("[Clipo OCR] no text extracted for %@", id.uuidString)
                return
            }
            let preview = text.prefix(80).replacingOccurrences(of: "\n", with: " ¶ ")
            NSLog("[Clipo OCR] %@ chars=%d: %@", id.uuidString, text.count, String(preview))
            await MainActor.run {
                AppState.shared.enqueueOCRResult(id: id, text: text)
            }
        }
    }

    /// Stash an OCR result and (re)schedule a drain. Multiple results
    /// within 200ms end up in the same context.save() + applyFilter.
    fileprivate func enqueueOCRResult(id: UUID, text: String) {
        pendingOCRUpdates[id] = text
        ocrDrainTimer?.invalidate()
        ocrDrainTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.drainOCRUpdates() }
        }
    }

    private func drainOCRUpdates() {
        guard !pendingOCRUpdates.isEmpty else { return }
        let pending = pendingOCRUpdates
        pendingOCRUpdates.removeAll(keepingCapacity: true)
        for (id, text) in pending {
            if let stored = allItems.first(where: { $0.id == id }) {
                stored.ocrText = text
            }
        }
        try? context.save()
        // If the user is mid-search and just typed a query that matches
        // any freshly-OCR'd text, one filter pass covers every batched
        // item at once.
        if !searchQuery.isEmpty {
            applyFilter()
        }
    }

    func delete(_ item: ClipItem) {
        context.delete(item)
        try? context.save()
        reload()
    }

    func clearAll() {
        // Preserve anything the user explicitly pinned (keyboard pin OR
        // Pinboard membership). Everything else gets wiped.
        try? context.delete(model: ClipItem.self, where: #Predicate {
            $0.pinShortcut == nil && $0.pinboard == nil
        })
        try? context.save()
        reload()
    }

    /// Full reload from SwiftData. Use for "hard" events (new copy, delete,
    /// clear, pinboard move, sort order change). For search and filter-tab
    /// swaps call `applyFilter()` directly — no DB hit.
    func reload() {
        let descriptor: FetchDescriptor<ClipItem>
        switch Defaults[.sortBy] {
        case .lastCopiedAt:
            descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)])
        case .firstCopiedAt:
            descriptor = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.firstCopiedAt, order: .reverse)])
        case .numberOfCopies:
            descriptor = FetchDescriptor<ClipItem>(sortBy: [
                SortDescriptor(\.numberOfCopies, order: .reverse),
                SortDescriptor(\.lastCopiedAt, order: .reverse)
            ])
        }
        allItems = (try? context.fetch(descriptor)) ?? []
        applyFilter()
        refreshPinboards()
    }

    /// Kept as an alias so existing callsites (and Defaults observers) can
    /// trigger a full reload with one verb. New code should call `reload()`
    /// or `applyFilter()` explicitly.
    func refresh() { reload() }

    /// Re-derive the visible `items` from the already-fetched `allItems`.
    /// Runs on every keystroke during search and every filter tab swap.
    /// Must stay O(N) in memory — no SwiftData round-trips.
    func applyFilter() {
        let filtered: [ClipItem]
        switch activeFilter {
        case .history:
            filtered = allItems
        case .images:
            filtered = allItems.filter { $0.primaryKind == .image }
        case .files:
            filtered = allItems.filter { $0.primaryKind == .file }
        case .pinboard(let id):
            filtered = allItems.filter { $0.pinboard?.id == id }
        }

        let nextItems: [ClipItem]
        if searchQuery.isEmpty {
            nextItems = filtered
        } else {
            nextItems = Self.search(filtered, query: searchQuery, mode: Defaults[.searchMode])
        }

        let nextSelected: UUID?
        if let id = selectedID, nextItems.contains(where: { $0.id == id }) {
            nextSelected = id
        } else {
            nextSelected = nextItems.first?.id
        }

        // Drop any multi-selected IDs that filtered out of view — a chip
        // sitting invisibly off-screen would confuse "N selected" counts.
        if !selectionOrder.isEmpty {
            let visible = Set(nextItems.map(\.id))
            let pruned = selectionOrder.filter { visible.contains($0) }
            if pruned.count != selectionOrder.count {
                selectionOrder = pruned
            }
        }

        // Publish items / selection inside a transaction that disables
        // implicit animations. SwiftUI's ForEach otherwise animates the
        // diff (cards sliding into place) when the list re-sorts during
        // a search or filter change.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            items = nextItems
            if selectedID != nextSelected {
                selectedID = nextSelected
            }
        }
    }

    /// Three modes share the same preprocessing (lowercase both sides) and
    /// differ only in the matcher:
    ///
    /// - `.exact`    matches when the title, lowercased, equals the query.
    /// - `.contains` matches when the title contains the query verbatim.
    /// - `.fuzzy`    runs a lightweight subsequence scorer: every query
    ///               character must appear in order, and items score higher
    ///               when the matches are clustered near the start of the
    ///               title. Re-ranked output beats a filtered-but-unsorted
    ///               list for "I half-remember what I copied" searches.
    static func search(_ items: [ClipItem], query: String, mode: SearchMode) -> [ClipItem] {
        let q = query.lowercased()
        guard !q.isEmpty else { return items }
        switch mode {
        case .exact:
            // Exact still matches against title only — matching OCR text
            // verbatim is almost never what "exact" means to a user.
            return items.filter { $0.title.lowercased() == q }
        case .contains:
            return items.filter { $0.searchHaystack().contains(q) }
        case .fuzzy:
            let scored: [(ClipItem, Int)] = items.compactMap { item in
                guard let score = fuzzyScore(query: q, in: item.searchHaystack()) else {
                    return nil
                }
                return (item, score)
            }
            // Higher score = better match. Stable sort keeps the original
            // recency order for ties.
            return scored.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// Subsequence match + cluster bonus. Returns nil when any query char
    /// can't be found in order. Keeps it honest (no false positives) while
    /// still tolerating typos within a word.
    private static func fuzzyScore(query: String, in target: String) -> Int? {
        let tChars = Array(target)
        let qChars = Array(query)
        guard !qChars.isEmpty, !tChars.isEmpty else { return nil }
        var score = 0
        var lastMatch = -1
        var firstMatch = -1
        var t = 0
        for q in qChars {
            var found = false
            while t < tChars.count {
                if tChars[t] == q {
                    if firstMatch == -1 { firstMatch = t }
                    // Adjacency bonus — matches next to each other score
                    // much higher than matches spread across the title.
                    if lastMatch == t - 1 { score += 5 } else { score += 1 }
                    lastMatch = t
                    t += 1
                    found = true
                    break
                }
                t += 1
            }
            if !found { return nil }
        }
        // Prefer matches that start early in the title.
        score += max(0, 10 - firstMatch)
        return score
    }

    private func refreshPinboards() {
        let descriptor = FetchDescriptor<Pinboard>(
            sortBy: [SortDescriptor(\.order)]
        )
        pinboards = (try? context.fetch(descriptor)) ?? []
        // If the currently-selected pinboard was removed, fall back to History.
        if case let .pinboard(id) = activeFilter,
           !pinboards.contains(where: { $0.id == id }) {
            activeFilter = .history
        }
    }

    /// Publicly callable variant for Defaults observers to trim the history
    /// after the user lowers `maxHistorySize`.
    func enforceHistoryLimitNow() {
        enforceHistoryLimit()
        refresh()
    }

    private func enforceHistoryLimit() {
        let limit = Defaults[.maxHistorySize]
        guard limit > 0 else { return }
        let descriptor = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.pinShortcut == nil && $0.pinboard == nil },
            sortBy: [SortDescriptor(\.lastCopiedAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        if all.count > limit {
            for stale in all.suffix(from: limit) {
                context.delete(stale)
            }
            try? context.save()
        }
    }

    // MARK: - Paste action

    var selectedItem: ClipItem? {
        items.first { $0.id == selectedID }
    }

    func pasteSelected() {
        // Multi-select takes priority — plain Enter on N selected cards
        // triggers the paste stack, not the single-item paste.
        if !selectionOrder.isEmpty {
            pasteStack()
            return
        }
        let item = selectedItem ?? items.first
        guard let item else { return }
        paste(item)
    }

    /// Default paste — honors `Defaults[.removeFormattingByDefault]`.
    /// Used by keyboard Enter, ⌥1–⌥9, double-click, and status-menu triggers.
    func paste(_ item: ClipItem) {
        performPaste(item, removeFormatting: Defaults[.removeFormattingByDefault])
    }

    /// Explicit override — always keeps formatting regardless of the default.
    func pasteWithFormatting(_ item: ClipItem) {
        performPaste(item, removeFormatting: false)
    }

    /// Explicit override — always strips formatting regardless of the default.
    func pasteAsPlainText(_ item: ClipItem) {
        performPaste(item, removeFormatting: true)
    }

    private func performPaste(_ item: ClipItem, removeFormatting: Bool) {
        bumpRecency(item)
        // 1. Stage the item on the system pasteboard BEFORE closing.
        ClipboardEngine.shared.copy(item, removeFormatting: removeFormatting)
        // 2. Close our panel instantly so the previous app regains keyboard focus.
        appDelegate?.closePanel()
        // 3. Let the window server deliver the focus change, then synthesize ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Paster.paste()
            // Silent confirmation — the panel is gone by now, so a brief
            // menu-bar checkmark tells the user "the paste fired" without
            // forcing a popup or notification.
            AppState.shared.appDelegate?.flashStatusIcon()
        }
    }

    /// Writes the item back to the system clipboard (without pasting) and
    /// closes the panel. Used by the "Copy Again" menu item and the ⌥⏎
    /// shortcut. The item is also promoted to the front of the MRU.
    func copyAgain(_ item: ClipItem) {
        bumpRecency(item)
        ClipboardEngine.shared.copy(item)
        appDelegate?.closePanel()
        appDelegate?.flashStatusIcon()
    }

    /// Promote an item to "most recent" status so it moves to the front of
    /// the carousel after being used. Runs before every internal copy/paste.
    ///
    /// Keeps paste latency flat: instead of re-fetching from SwiftData (which
    /// shows up as a visible re-sort flash when the panel closes), we just
    /// move the item to the head of `allItems` in memory and re-derive the
    /// visible list. The new `lastCopiedAt` is persisted, so the next
    /// full `reload()` produces the same ordering.
    private func bumpRecency(_ item: ClipItem) {
        item.lastCopiedAt = .now
        item.numberOfCopies += 1
        try? context.save()
        if let idx = allItems.firstIndex(where: { $0.id == item.id }) {
            allItems.remove(at: idx)
        }
        allItems.insert(item, at: 0)
        applyFilter()
    }

    // MARK: - Pinboard operations

    func createPinboard(name: String) {
        let next = (pinboards.map(\.order).max() ?? -1) + 1
        let board = Pinboard(name: name, order: next)
        context.insert(board)
        try? context.save()
        refreshPinboards()
    }

    /// Reloads the script list from disk into the in-memory cache. Call at
    /// launch, when the user clicks Reload in the Scripts settings pane,
    /// and after editing/adding/removing .js files.
    func refreshScripts() {
        scripts = ScriptLoader.loadAll()
    }

    /// Installs the default "Important" pinboard on first launch. Runs once
    /// (guarded by `Defaults[.didInstallDefaultPinboards]`) so users who later
    /// delete it won't see it resurrected on the next launch.
    func installDefaultPinboardsIfNeeded() {
        guard !Defaults[.didInstallDefaultPinboards] else { return }
        let existing = (try? context.fetch(FetchDescriptor<Pinboard>())) ?? []
        if existing.isEmpty {
            let important = Pinboard(
                name: "Important",
                accentColorHex: "#FF3B30",
                order: 0
            )
            context.insert(important)
            try? context.save()
            refreshPinboards()
        }
        Defaults[.didInstallDefaultPinboards] = true
    }

    /// Empty a Pinboard without destroying the board itself. Every item
    /// that belonged to it is moved back to History (pinboard = nil).
    func clearPinboard(_ board: Pinboard) {
        for item in allItems where item.pinboard?.id == board.id {
            item.pinboard = nil
        }
        try? context.save()
        applyFilter()
    }

    /// Delete a Pinboard; its items survive (pinboard just becomes nil).
    /// The board itself is removed from the top-bar filter list.
    func deletePinboard(_ board: Pinboard) {
        for item in allItems where item.pinboard?.id == board.id {
            item.pinboard = nil
        }
        context.delete(board)
        try? context.save()
        // If this board was the active filter, fall back to History.
        if case let .pinboard(id) = activeFilter, id == board.id {
            activeFilter = .history
        }
        refreshPinboards()
        applyFilter()
    }

    func move(_ item: ClipItem, to board: Pinboard?) {
        item.pinboard = board
        try? context.save()
        // Membership drives both the Pinboard filter and the card footer
        // chip — re-derive the visible list, but no DB round-trip needed.
        applyFilter()
    }

    // MARK: - Navigation

    func selectNext() {
        guard !items.isEmpty else { return }
        if let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[min(idx + 1, items.count - 1)].id
        } else {
            selectedID = items.first?.id
        }
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        if let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) {
            selectedID = items[max(idx - 1, 0)].id
        } else {
            selectedID = items.first?.id
        }
    }

    func selectByIndex(_ index: Int) {
        guard index >= 0, index < items.count else { return }
        selectedID = items[index].id
    }

    // MARK: - Multi-selection

    /// ⌘+click: add/remove a single card from the selection. Repeated
    /// toggles cycle the card in and out without affecting other members.
    /// After toggling we move `selectedID` to this item so keyboard focus
    /// follows the user's last intent.
    func toggleInSelection(_ id: UUID) {
        if let idx = selectionOrder.firstIndex(of: id) {
            selectionOrder.remove(at: idx)
        } else {
            selectionOrder.append(id)
        }
        selectedID = id
    }

    /// Shift+click / Shift+arrow: replace the selection with the range
    /// between the current anchor and `id`, filling in **carousel order**
    /// (left → right = newest → oldest) so the paste sequence matches the
    /// user's visual intuition.
    func extendSelection(to id: UUID) {
        guard let anchor = selectedID,
              let a = items.firstIndex(where: { $0.id == anchor }),
              let b = items.firstIndex(where: { $0.id == id }) else {
            // No anchor — treat as plain select.
            selectionOrder = [id]
            selectedID = id
            return
        }
        let lo = min(a, b), hi = max(a, b)
        let indices = a <= b ? Array(lo...hi) : Array((lo...hi).reversed())
        selectionOrder = indices.map { items[$0].id }
        selectedID = id
    }

    /// ⌘A: pick up every currently visible card in current sort order.
    func selectAll() {
        selectionOrder = items.map(\.id)
        selectedID = items.first?.id
    }

    /// First Escape press (or any non-modified click) clears the multi
    /// selection and drops back to single-focus mode on the last anchor.
    func clearMultiSelection() {
        selectionOrder.removeAll(keepingCapacity: false)
    }

    // MARK: - Batch actions

    /// Pastes every multi-selected card in click order, separated by \n.
    /// Non-text kinds (image, color) are filtered out because the merged
    /// string form wouldn't carry them faithfully. When the selection is
    /// ENTIRELY non-text we beep + flash the footer hint bar instead of
    /// silently no-op'ing, so the user knows their action had no target.
    func pasteStack() {
        let ordered = selectionOrder.compactMap { id in
            items.first { $0.id == id }
        }
        guard !ordered.isEmpty else { return }

        // Pastable kinds: plain text, URLs, files. Files contribute their
        // POSIX paths (matches what the engine's single-file paste emits).
        let pastable = ordered.filter { item in
            switch item.primaryKind {
            case .text, .url, .file: return true
            case .image, .color:     return false
            }
        }
        guard !pastable.isEmpty else {
            NSSound.beep()
            flashStackError = true
            // Auto-clear the banner after 1.8s so it doesn't linger.
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                self?.flashStackError = false
            }
            return
        }

        let combined = pastable.map { item -> String in
            if !item.fileURLs.isEmpty {
                return item.fileURLs.map(\.path).joined(separator: "\n")
            }
            return item.text ?? item.title
        }.joined(separator: "\n")

        // Bump recency on every pasted item, first-clicked landing at the
        // top of allItems so the carousel reflects "this was the latest
        // action" afterwards. Reverse-iterate so pastable[0] ends at front.
        let now = Date.now
        for item in pastable {
            item.lastCopiedAt = now
            item.numberOfCopies += 1
        }
        try? context.save()
        for item in pastable.reversed() {
            if let idx = allItems.firstIndex(where: { $0.id == item.id }) {
                allItems.remove(at: idx)
            }
            allItems.insert(item, at: 0)
        }
        applyFilter()

        // Write the combined blob to the pasteboard with Clipo's own marker
        // so the engine doesn't re-ingest it as a new item.
        ClipboardEngine.shared.writeText(combined)
        clearMultiSelection()

        appDelegate?.closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Paster.paste()
            AppState.shared.appDelegate?.flashStatusIcon()
        }
    }

    /// Delete every multi-selected card in one transaction. Unlike the
    /// single-item delete path, we reload() at the end because multiple
    /// removals may change the tail of allItems in ways that are messier
    /// to reconcile than just re-fetching.
    func deleteSelection() {
        guard !selectionOrder.isEmpty else { return }
        let ids = Set(selectionOrder)
        for item in allItems where ids.contains(item.id) {
            context.delete(item)
        }
        try? context.save()
        clearMultiSelection()
        reload()
    }

    /// Move every multi-selected card to (or out of) a Pinboard at once.
    func moveSelection(to board: Pinboard?) {
        guard !selectionOrder.isEmpty else { return }
        let ids = Set(selectionOrder)
        for item in allItems where ids.contains(item.id) {
            item.pinboard = board
        }
        try? context.save()
        // Selection survives — user often moves several items then wants
        // to move them again or continue pinning. Drop only on Esc.
        applyFilter()
    }
}
