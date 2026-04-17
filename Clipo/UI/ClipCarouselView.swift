import Defaults
import SwiftUI

struct ClipCarouselView: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: PanelFocus?

    @State private var filterJustChanged = false

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
                                    Button("Paste") { state.paste(item) }
                                    Button("Paste with Formatting") { state.pasteWithFormatting(item) }
                                    Button("Copy Again") {
                                        ClipboardEngine.shared.copy(item)
                                        state.appDelegate?.closePanel()
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
                                    Button("Delete", role: .destructive) { state.delete(item) }
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
            .onChange(of: state.selectedID) { _, new in
                guard let new else { return }
                if filterJustChanged {
                    // Filter just changed — scroll is handled above without animation.
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
                // 1-9 → quick paste the corresponding visible card.
                if let d = char.wholeNumberValue, d >= 1, d <= 9 {
                    state.selectByIndex(d - 1)
                    state.pasteSelected()
                    return .handled
                }
                // Any other printable char → switch to search field first, then
                // inject the character asynchronously so the TextField has
                // already taken focus before the observable value changes.
                if char.isLetter || "-_.@/:".contains(char) {
                    let chars = press.characters
                    focus = .search
                    DispatchQueue.main.async {
                        state.searchQuery.append(chars)
                        state.refresh()
                    }
                    return .handled
                }
                return .ignored
            }
        }
        .frame(height: DesignTokens.cardHeight + 24)
    }

    @ViewBuilder
    private func scriptMenu(for item: ClipItem) -> some View {
        let disabled = Defaults[.disabledScriptIDs]
        let enabled = ScriptLoader.loadAll().filter { !disabled.contains($0.id) }
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
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
            Text("Nothing copied yet")
                .font(DesignTokens.rounded(12, weight: .medium))
                .foregroundStyle(DesignTokens.TextColor.secondary)
            Text("Copy with ⌘C to get started")
                .font(DesignTokens.rounded(10))
                .foregroundStyle(DesignTokens.TextColor.tertiary)
        }
        .frame(width: DesignTokens.cardWidth, height: DesignTokens.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cardRadius, style: .continuous)
                .strokeBorder(
                    Color.black.opacity(0.10),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
    }
}
