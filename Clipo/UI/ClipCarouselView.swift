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

                    HStack(spacing: DesignTokens.cardSpacing) {
                        if state.items.isEmpty {
                            EmptyCard()
                        } else {
                            ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                                ClipCardView(
                                    item: item,
                                    index: index + 1,
                                    isSelected: state.selectedID == item.id
                                )
                                .id(item.id)
                                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
                                .overlay(
                                    ClickCatcher { clickCount in
                                        if clickCount >= 2 {
                                            state.paste(item)
                                        } else {
                                            state.selectedID = item.id
                                            focus = .carousel
                                            state.appDelegate?.closePreview()
                                        }
                                    }
                                )
                                .contextMenu {
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
            .onKeyPress(.leftArrow)  { state.selectPrevious(); return .handled }
            .onKeyPress(.rightArrow) { state.selectNext();     return .handled }
            .onKeyPress(.upArrow)    { focus = .search;        return .handled }
            .onKeyPress(.return)     { state.pasteSelected();  return .handled }
            .onKeyPress { press in
                guard press.modifiers.isEmpty, let char = press.characters.first else {
                    return .ignored
                }
                // Space → open the preview window for the selected item.
                if char == " " {
                    if let item = state.selectedItem ?? state.items.first {
                        state.appDelegate?.showPreview(item: item)
                    }
                    return .handled
                }
                // Any printable char (letters, digits, allowed punctuation)
                // routes to the search field. Quick-paste is ⌥1–⌥9 only —
                // plain digits type into search like any other key.
                if char.isLetter || char.isNumber || "-_.@/:".contains(char) {
                    let chars = press.characters
                    focus = .search
                    DispatchQueue.main.async {
                        // Mutating searchQuery triggers the SearchField's
                        // onChange which already calls applyFilter(); calling
                        // it explicitly here would double the work.
                        state.searchQuery.append(chars)
                    }
                    return .handled
                }
                return .ignored
            }
        }
        .frame(height: DesignTokens.cardHeight + 24)
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
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            // Dashed border needs to read at a glance — 0.10 felt like a ghost.
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .strokeBorder(
                    Color.black.opacity(0.18),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }
}
