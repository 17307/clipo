import Defaults
import KeyboardShortcuts
import SwiftUI

struct ClipCarouselView: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: PanelFocus?

    @State private var filterJustChanged = false
    /// Tracks the searchQuery value at the time of the last selection scroll
    /// so we can tell "user navigated within the same query" from "query
    /// changed, treat this as a filter transition".
    @State private var lastSearchQuery: String = ""

    /// Scroll-to sentinel ID for "the very start of the carousel".
    private static let startAnchorID = "__carousel_start"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Zero-width sentinel at x=0 — sits BEFORE the leading
                    // padding so scrollTo(.leading) on it produces a real
                    // "scroll offset 0" (padding stays visible).
                    Color.clear
                        .frame(width: 0, height: 1)
                        .id(Self.startAnchorID)

                    // LazyHStack so a 500-item history doesn't materialize
                    // 500 ClipCardView bodies — only the roughly-7 visible
                    // cards and their immediate neighbours get built.
                    LazyHStack(spacing: DesignTokens.cardSpacing) {
                        if state.items.isEmpty {
                            EmptyCard()
                        } else {
                            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                ClipCardView(
                                    item: item,
                                    index: index + 1,
                                    isSelected: state.selectedID == item.id,
                                    multiPosition: state.selectionIndex(of: item.id),
                                    searchQuery: state.searchQuery
                                )
                                .id(item.id)
                                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
                                .overlay(
                                    ClickCatcher(
                                        onClick: { clickCount, mods in
                                            handleClick(on: item, clickCount: clickCount, mods: mods)
                                        },
                                        onRightClick: {
                                            handleRightClick(on: item)
                                        }
                                    )
                                )
                                .contextMenu { contextMenu(for: item) }
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.panelHorizontalPadding)
                }
                .padding(.vertical, 6)
                // Force a fresh view hierarchy per filter so SwiftUI doesn't
                // animate the diff between, e.g., History and Images.
                .id(state.activeFilter)
                // Suppress ForEach diff animations when items change due to
                // the search query — filtering should feel instant, not have
                // cards fly in/out on every keystroke.
                .animation(nil, value: state.searchQuery)
            }
            .scrollIndicators(.hidden)
            .onChange(of: state.activeFilter) { _, _ in
                // Snap to the very beginning (offset 0) without animation.
                filterJustChanged = true
                proxy.scrollTo(Self.startAnchorID, anchor: .leading)
                // Clear the flag on the next runloop tick, after selectedID's
                // onChange below has had a chance to read it.
                DispatchQueue.main.async { filterJustChanged = false }
            }
            .onChange(of: state.openToken) { _, _ in
                // Panel re-opened — items may have re-sorted (e.g. after
                // paste bumped one to the top) but the ScrollView keeps its
                // pixel offset. Snap back to the start.
                filterJustChanged = true
                proxy.scrollTo(Self.startAnchorID, anchor: .leading)
                DispatchQueue.main.async { filterJustChanged = false }
            }
            .onChange(of: state.selectedID) { _, new in
                guard let new else { return }
                if filterJustChanged {
                    // Filter just changed — scroll is handled above without animation.
                    return
                }
                if state.searchQuery != lastSearchQuery {
                    // Search text changed since the last selection scroll.
                    // This selectedID change is part of a filter transition,
                    // not manual navigation — snap to start without spring.
                    lastSearchQuery = state.searchQuery
                    proxy.scrollTo(Self.startAnchorID, anchor: .leading)
                    return
                }
                withAnimation(DesignTokens.selectSpring) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
            .focusable()
            .focused($focus, equals: .carousel)
            .focusEffectDisabled()
            .onKeyPress { press in
                handleCarouselKey(press)
            }
        }
        .frame(height: DesignTokens.cardHeight + 24)
    }

    /// Context menu builder. When the right-clicked card is part of an
    /// active multi-selection, the menu switches to batch actions; otherwise
    /// it shows the single-item menu. Right-clicking a card that isn't in
    /// the selection uses the single-item menu but doesn't clear the
    /// selection — Mac convention is lenient here, and the user can always
    /// hit Esc to clear.
    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        if state.isMultiSelecting && state.isInSelection(item.id) {
            let count = state.selectionOrder.count
            Button("Paste Stack (\(count) items)") {
                state.pasteStack()
            }
            Divider()
            multiPinMenu()
            if hasAnyPinnedInSelection {
                Button("Remove All from Pinboard") {
                    state.moveSelection(to: nil)
                }
            }
            Divider()
            Button("Delete \(count) Items", role: .destructive) {
                state.deleteSelection()
            }
        } else {
            Button(titled("Paste as Plain Text", shortcut: .pastePlain)) {
                state.pasteAsPlainText(item)
            }
            Button(titled("Paste with Formatting", shortcut: .pasteFormatted)) {
                state.pasteWithFormatting(item)
            }
            Button(titled("Copy Again", shortcut: .copyAgain)) {
                state.copyAgain(item)
            }
            Divider()
            pinMenu(for: item)
            if let board = item.pinboard {
                Button("Remove from \(board.name)") {
                    state.move(item, to: nil)
                }
            }
            Divider()
            scriptMenu(for: item)
            Divider()
            Button("Delete", role: .destructive) {
                state.delete(item)
            }
        }
    }

    /// True if any item in the current multi-selection is already pinned
    /// to a Pinboard — drives whether "Remove All from Pinboard" is offered.
    private var hasAnyPinnedInSelection: Bool {
        let ids = Set(state.selectionOrder)
        return state.items.contains { ids.contains($0.id) && $0.pinboard != nil }
    }

    /// Pin-to submenu for the batch case — same list of pinboards, but
    /// the chosen destination is applied to every multi-selected card.
    @ViewBuilder
    private func multiPinMenu() -> some View {
        Menu("Pin All to") {
            if state.pinboards.isEmpty {
                Text("No pinboards yet")
            } else {
                ForEach(state.pinboards) { board in
                    Button(board.name) {
                        state.moveSelection(to: board)
                    }
                }
            }
            Divider()
            Button("Manage Pinboards…") {
                state.appDelegate?.openSettings()
            }
        }
    }

    /// Unified key handler for the carousel. Shift-arrows extend the multi-
    /// selection from the current anchor, plain arrows navigate single-focus,
    /// ⌘A selects all, backspace deletes the current (or multi) selection,
    /// Space opens the preview, printable chars route to search.
    private func handleCarouselKey(_ press: KeyPress) -> KeyPress.Result {
        // ⌘A → select all visible cards.
        if press.modifiers.contains(.command),
           press.characters.lowercased() == "a" {
            state.selectAll()
            return .handled
        }
        switch press.key {
        case .leftArrow:
            if press.modifiers.contains(.shift) {
                extendSelection(direction: -1)
            } else {
                state.selectPrevious()
            }
            return .handled
        case .rightArrow:
            if press.modifiers.contains(.shift) {
                extendSelection(direction: 1)
            } else {
                state.selectNext()
            }
            return .handled
        case .upArrow:
            focus = .search
            return .handled
        case .return:
            state.pasteSelected()
            return .handled
        case .delete:
            // Backspace / delete-above-return. Only consume when a multi
            // selection exists so the key still works in the search field.
            if !state.selectionOrder.isEmpty {
                state.deleteSelection()
                return .handled
            }
            return .ignored
        default:
            break
        }
        // Space → preview (only when unmodified).
        guard press.modifiers.isEmpty, let char = press.characters.first else {
            return .ignored
        }
        if char == " " {
            if let item = state.selectedItem ?? state.items.first {
                state.appDelegate?.showPreview(item: item)
            }
            return .handled
        }
        // Printable → route to search field.
        if char.isLetter || char.isNumber || "-_.@/:".contains(char) {
            let chars = press.characters
            focus = .search
            DispatchQueue.main.async {
                state.searchQuery.append(chars)
            }
            return .handled
        }
        return .ignored
    }

    /// Shift+arrow selection extension. Picks the card one step over in the
    /// given direction and hands off to AppState.extendSelection so click
    /// and keyboard agree on anchor semantics.
    private func extendSelection(direction: Int) {
        guard let anchor = state.selectedID,
              let idx = state.items.firstIndex(where: { $0.id == anchor }) else {
            return
        }
        let next = idx + direction
        guard next >= 0, next < state.items.count else { return }
        state.extendSelection(to: state.items[next].id)
    }

    /// Finder convention for right-click + multi-selection:
    /// - Right-click on a card ALREADY in the selection: keep the
    ///   selection, context menu will render the batch actions.
    /// - Right-click on a card NOT in the selection: clear the multi,
    ///   single-focus this card, then let the single-item menu show.
    /// Prevents the confusing state where a stale multi-highlight stays
    /// on screen while the user acts on a different card.
    private func handleRightClick(on item: ClipItem) {
        guard !state.isInSelection(item.id) else { return }
        state.clearMultiSelection()
        state.selectedID = item.id
    }

    /// Dispatches a carousel card click into the correct selection /
    /// paste path based on modifiers:
    /// - double click: paste (single item or stack if multi-selecting)
    /// - ⇧ + click: extend selection from the current anchor
    /// - ⌘ + click: toggle this card in/out of the multi-selection
    /// - plain click: clear any multi-selection and single-focus this card
    private func handleClick(on item: ClipItem, clickCount: Int, mods: NSEvent.ModifierFlags) {
        if clickCount >= 2 {
            if state.isMultiSelecting {
                state.pasteStack()
            } else {
                state.paste(item)
            }
            return
        }
        if mods.contains(.shift) {
            state.extendSelection(to: item.id)
            focus = .carousel
            return
        }
        if mods.contains(.command) {
            state.toggleInSelection(item.id)
            focus = .carousel
            return
        }
        // Plain click — collapse back to single-select on this card.
        state.clearMultiSelection()
        state.selectedID = item.id
        focus = .carousel
        state.appDelegate?.closePreview()
    }

    /// Suffix a menu item's title with the current binding's glyph so the
    /// shortcut is visible right in the context menu (e.g. "Delete  ⌫").
    /// Rebuilt whenever the menu opens, so Settings changes reflect live.
    private func titled(_ title: String, shortcut name: KeyboardShortcuts.Name) -> String {
        guard let s = KeyboardShortcuts.getShortcut(for: name) else { return title }
        let glyph = s.description.trimmingCharacters(in: .whitespaces)
        return glyph.isEmpty ? title : "\(title)  \(glyph)"
    }

    @ViewBuilder
    private func scriptMenu(for item: ClipItem) -> some View {
        let disabled = Defaults[.disabledScriptIDs]
        let enabled = state.scripts.filter { !disabled.contains($0.id) }
        Menu("Run Script") {
            if enabled.isEmpty {
                Text("No enabled scripts")
                Divider()
                Button("Open Scripts Settings…") {
                    state.appDelegate?.openSettings()
                }
            } else {
                ForEach(enabled) { script in
                    Button {
                        state.appDelegate?.runScript(script, on: item)
                    } label: {
                        Label(script.name, systemImage: script.icon)
                    }
                }
                Divider()
                Button("Manage Scripts…") {
                    state.appDelegate?.openSettings()
                }
            }
        }
    }

    @ViewBuilder
    private func pinMenu(for item: ClipItem) -> some View {
        Menu("Pin to") {
            if state.pinboards.isEmpty {
                Text("No pinboards yet")
            } else {
                ForEach(state.pinboards) { board in
                    Button {
                        state.move(item, to: board)
                    } label: {
                        if item.pinboard?.id == board.id {
                            Label(board.name, systemImage: "checkmark")
                        } else {
                            Text(board.name)
                        }
                    }
                }
            }
            Divider()
            Button("Manage Pinboards…") {
                state.appDelegate?.openSettings()
            }
        }
    }
}

private struct EmptyCard: View {
    @Default(.ignoreEvents) private var isPaused

    var accessibilityText: String {
        isPaused
            ? "Clipboard monitoring is paused. Resume in Settings, Advanced."
            : "Nothing copied yet. Copy something with Command C to get started."
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isPaused ? "pause.circle" : "doc.on.clipboard")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(isPaused ? DesignTokens.accent.opacity(0.70) : DesignTokens.TextColor.tertiary)
            Text(isPaused ? "Clipboard monitoring is paused" : "Nothing copied yet")
                .font(DesignTokens.rounded(12, weight: .medium))
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .multilineTextAlignment(.center)
            Text(isPaused ? "Resume in Settings → Advanced" : "Copy with ⌘C to get started")
                .font(DesignTokens.rounded(10))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(Color(
                    light: .white.opacity(0.5),
                    dark: Color(white: 0.15).opacity(0.55)
                ))
        )
        .overlay(
            // Dashed border needs to read at a glance in both appearances.
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
