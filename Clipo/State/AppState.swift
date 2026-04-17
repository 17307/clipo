import AppKit
import Defaults
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    var items: [ClipItem] = []
    var activeFilter: ClipFilter = .history
    var pinboards: [Pinboard] = []
    var selectedID: UUID?
    var searchQuery: String = ""

    /// True while the user is holding the Option key inside the panel.
    /// Used to show ⌥1–⌥9 quick-paste badges over each card.
    var isOptionDown: Bool = false

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
        refresh()
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

    init() {
        refresh()
    }

    // MARK: - History operations

    func add(_ item: ClipItem) {
        // Dedup — if an existing item supersedes the new one, just bump its lastCopiedAt.
        let descriptor = FetchDescriptor<ClipItem>()
        if let existing = (try? context.fetch(descriptor))?.first(where: { $0.supersedes(item) }) {
            existing.lastCopiedAt = .now
            existing.numberOfCopies += 1
            try? context.save()
            refresh()
            return
        }

        context.insert(item)
        try? context.save()
        enforceHistoryLimit()
        refresh()
    }

    func delete(_ item: ClipItem) {
        context.delete(item)
        try? context.save()
        refresh()
    }

    func clearAll() {
        // Preserve anything the user explicitly pinned (keyboard pin OR
        // Pinboard membership). Everything else gets wiped.
        try? context.delete(model: ClipItem.self, where: #Predicate {
            $0.pinShortcut == nil && $0.pinboard == nil
        })
        try? context.save()
        refresh()
    }

    func refresh() {
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
        let all = (try? context.fetch(descriptor)) ?? []

        // Filter by the active top-bar filter. Items pinned to a Pinboard
        // still show in History — the Pinboard is an extra categorization,
        // not a move.
        let filtered: [ClipItem]
        switch activeFilter {
        case .history:
            filtered = all
        case .images:
            filtered = all.filter { $0.primaryKind == .image }
        case .files:
            filtered = all.filter { $0.primaryKind == .file }
        case .pinboard(let id):
            filtered = all.filter { $0.pinboard?.id == id }
        }

        // Apply search
        if searchQuery.isEmpty {
            items = filtered
        } else {
            let q = searchQuery.lowercased()
            items = filtered.filter { $0.title.lowercased().contains(q) }
        }

        // Keep selection valid
        if let id = selectedID, !items.contains(where: { $0.id == id }) {
            selectedID = items.first?.id
        } else if selectedID == nil {
            selectedID = items.first?.id
        }

        refreshPinboards()
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
        let item = selectedItem ?? items.first
        guard let item else { return }
        paste(item)
    }

    /// Default paste — honors `Defaults[.removeFormattingByDefault]`.
    func paste(_ item: ClipItem) {
        performPaste(item, removeFormatting: Defaults[.removeFormattingByDefault])
    }

    /// Explicit override — always keeps formatting regardless of the default.
    func pasteWithFormatting(_ item: ClipItem) {
        performPaste(item, removeFormatting: false)
    }

    private func performPaste(_ item: ClipItem, removeFormatting: Bool) {
        // 1. Stage the item on the system pasteboard BEFORE closing.
        ClipboardEngine.shared.copy(item, removeFormatting: removeFormatting)
        // 2. Close our panel instantly so the previous app regains keyboard focus.
        appDelegate?.closePanel()
        // 3. Let the window server deliver the focus change, then synthesize ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Paster.paste()
        }
    }

    // MARK: - Pinboard operations

    func createPinboard(name: String) {
        let next = (pinboards.map(\.order).max() ?? -1) + 1
        let board = Pinboard(name: name, order: next)
        context.insert(board)
        try? context.save()
        refreshPinboards()
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

    func move(_ item: ClipItem, to board: Pinboard?) {
        item.pinboard = board
        try? context.save()
        refresh()
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
}
