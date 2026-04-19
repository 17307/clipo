import AppKit
import Defaults
import SwiftUI

enum PanelFocus: Hashable {
    case search
    case carousel
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focus: PanelFocus?
    @Default(.showFooterHints) private var showFooterHints

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .ignoresSafeArea()
            DesignTokens.Surface.panelWash
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                TopBarView(focus: $focus)
                    .padding(.horizontal, DesignTokens.panelHorizontalPadding)
                    .padding(.top, DesignTokens.panelTopPadding)
                    .padding(.bottom, 10)

                if !state.isAccessibilityGranted {
                    AccessibilityBanner()
                        .padding(.horizontal, DesignTokens.panelHorizontalPadding)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ClipCarouselView(focus: $focus)

                if showFooterHints {
                    FooterHintBar()
                        .padding(.horizontal, DesignTokens.panelHorizontalPadding)
                        .padding(.bottom, DesignTokens.panelBottomPadding)
                }
            }
        }
        .onAppear {
            // Default focus → the card carousel. Arrow keys navigate directly;
            // any printable key typed there is routed to the search field.
            DispatchQueue.main.async { focus = .carousel }
        }
        .onChange(of: state.openToken) { _, _ in
            // The panel re-opened — reset focus back to the carousel.
            DispatchQueue.main.async { focus = .carousel }
        }
        .onChange(of: state.focusResetToken) { _, _ in
            // A preview just closed — re-assert carousel focus so keyboard
            // navigation resumes, but don't touch scroll position.
            DispatchQueue.main.async { focus = .carousel }
        }
        .onKeyPress(.escape) {
            state.appDelegate?.closePanel()
            return .handled
        }
        .onKeyPress { press in
            if press.modifiers.contains(.command) {
                // ⌘, opens Settings
                if press.characters == "," {
                    state.appDelegate?.openSettings()
                    return .handled
                }
                // ⌘1-9 picks the Nth tab in the top filter bar.
                if let c = press.characters.first,
                   let d = c.wholeNumberValue, d >= 1, d <= 9 {
                    state.selectFilterByIndex(d - 1)
                    return .handled
                }
            }
            return .ignored
        }
    }
}

// MARK: - Top bar

private struct TopBarView: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: PanelFocus?
    @Default(.accentColorHex) private var accentHex

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                    .shadow(color: accent.opacity(0.5), radius: 4)
                Text("Clipo")
                    .font(DesignTokens.rounded(13, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.primary)
                    .tracking(0.4)
            }

            PinboardTabsView(defaultAccent: accent)

            Spacer(minLength: 10)

            SearchFieldView(focus: $focus, accent: accent)
                .frame(width: 260)
        }
    }
}

// MARK: - Filter tabs (History | Images | Files | …pinboards)

private struct PinboardTabsView: View {
    @Environment(AppState.self) private var state
    let defaultAccent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(state.topBarFilters, id: \.self) { filter in
                TabChip(
                    title: title(for: filter),
                    icon: filter.builtInIcon,
                    accent: accent(for: filter),
                    isSelected: state.activeFilter == filter
                ) {
                    state.setFilter(filter)
                }
                .contextMenu { tabMenu(for: filter) }
            }
        }
    }

    /// Built-in tabs have nothing to configure; pinboard tabs offer
    /// clear/delete so users don't have to open Settings every time
    /// they want to purge a board.
    @ViewBuilder
    private func tabMenu(for filter: ClipFilter) -> some View {
        if let board = state.pinboard(for: filter) {
            Button("Clear items") {
                state.clearPinboard(board)
            }
            Button("Delete pinboard", role: .destructive) {
                state.deletePinboard(board)
            }
            Divider()
            Button("Manage Pinboards…") {
                state.appDelegate?.openSettings()
            }
        } else {
            Button("Manage Pinboards…") {
                state.appDelegate?.openSettings()
            }
        }
    }

    private func title(for filter: ClipFilter) -> String {
        if let t = filter.builtInTitle { return t }
        if let board = state.pinboard(for: filter) { return board.name }
        return "?"
    }

    private func accent(for filter: ClipFilter) -> Color {
        if let c = filter.builtInAccent { return c }
        if case .history = filter { return defaultAccent }
        if let board = state.pinboard(for: filter) {
            return Color(hex: board.accentColorHex) ?? defaultAccent
        }
        return defaultAccent
    }
}

extension Pinboard: Identifiable {}

private struct TabChip: View {
    let title: String
    /// SF Symbol for built-in filters (History / Images / Files).
    var icon: String? = nil
    var accent: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                leadingGlyph
                Text(title)
                    .font(DesignTokens.rounded(11.5, weight: .medium))
                    .tracking(0.2)
            }
            .foregroundStyle(isSelected ? accent : DesignTokens.TextColor.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    if isSelected {
                        Capsule().fill(accent.opacity(0.14))
                        Capsule().strokeBorder(accent.opacity(0.55), lineWidth: 1)
                    } else if hovering {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .pointingHand()
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : DesignTokens.hoverAnim, value: hovering)
        .animation(reduceMotion ? nil : DesignTokens.selectSpring, value: isSelected)
    }

    /// Built-in filters show an SF Symbol; user pinboards show a colored
    /// dot matching their accent, visible even when not selected so the
    /// tab's "color identity" is always readable.
    @ViewBuilder
    private var leadingGlyph: some View {
        if let icon {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
        } else {
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
                .overlay(
                    Circle()
                        .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                )
        }
    }
}

// MARK: - Search field

private struct SearchFieldView: View {
    @Environment(AppState.self) private var state
    @FocusState.Binding var focus: PanelFocus?
    let accent: Color

    var body: some View {
        @Bindable var state = state
        let isActive = focus == .search
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? accent : DesignTokens.TextColor.tertiary)
            TextField("Type to search…", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(DesignTokens.rounded(12, weight: .regular))
                .foregroundStyle(DesignTokens.TextColor.primary)
                .focused($focus, equals: .search)
                .onChange(of: state.searchQuery) { _, _ in state.applyFilter() }
                .onSubmit { state.pasteSelected() }
                .onKeyPress(.downArrow) {
                    focus = .carousel
                    return .handled
                }
                .onKeyPress(.leftArrow) {
                    // Only navigate cards when the search field is empty —
                    // otherwise Left should move the text cursor as usual.
                    guard state.searchQuery.isEmpty else { return .ignored }
                    state.selectPrevious()
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    // Users typing a query and then habitually reaching
                    // for → to move into the results expected that motion
                    // to land on the next card, not sit at an already-
                    // at-end caret. So: right arrow at (or past) the end
                    // of the query jumps focus into the carousel and
                    // advances the selection by one — same as hitting
                    // Down then Right, in a single keystroke. Right
                    // arrow anywhere inside the text still moves the
                    // caret as normal.
                    guard caretIsAtEndOfQuery() else { return .ignored }
                    state.selectNext()
                    focus = .carousel
                    return .handled
                }
            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                    state.applyFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.TextColor.tertiary)
                }
                .buttonStyle(.plain)
                .pointingHand()
                .accessibilityLabel("Clear search")
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.inputRadius, style: .continuous)
                .fill(Color.primary.opacity(isActive ? 0.07 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.inputRadius, style: .continuous)
                .strokeBorder(
                    isActive ? accent.opacity(0.55) : Color.primary.opacity(0.10),
                    lineWidth: 1
                )
        )
        .animation(DesignTokens.hoverAnim, value: isActive)
    }

    /// True when the text cursor sits at the very end of the current
    /// query (or the query is empty, i.e. there's nowhere for the
    /// cursor to be except "the end"). SwiftUI's `TextField` on macOS
    /// delegates editing to a shared field editor — an `NSTextView` —
    /// that becomes the window's `firstResponder` while the field is
    /// focused. We read its selected range to decide whether → should
    /// move the caret (cursor is mid-text) or switch over to the
    /// carousel (cursor is at end).
    ///
    /// Collapsed-selection case (length == 0) must land exactly on the
    /// last character offset. When the user has a text selection
    /// (length > 0), right arrow first collapses it to the end without
    /// navigating, which matches how every other macOS text field
    /// behaves — only the next press navigates.
    private func caretIsAtEndOfQuery() -> Bool {
        if state.searchQuery.isEmpty { return true }
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        let range = editor.selectedRange()
        let length = (editor.string as NSString).length
        return range.length == 0 && range.location == length
    }
}

// MARK: - Footer hint bar

private struct FooterHintBar: View {
    @Environment(AppState.self) private var state
    @Default(.accentColorHex) private var accentHex
    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        // Pure decorative keyboard hints. VoiceOver users already get the
        // same shortcuts announced via the cards' accessibilityHint, so
        // hide this whole row to avoid repeating the glyphs on every pane
        // landing.
        Group {
            if state.flashStackError {
                errorBody
            } else if state.isMultiSelecting {
                multiSelectBody
            } else {
                hintsBody
            }
        }
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.2), value: state.flashStackError)
    }

    /// Flash shown for ~1.8s when the user hits ⏎ on a multi-selection
    /// that contained no pastable items (only images/colors).
    private var errorBody: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text("No text to paste in this selection")
                .font(DesignTokens.rounded(11, weight: .semibold))
                .foregroundStyle(DesignTokens.TextColor.primary)
            Text("Only text, URLs, and file paths can be stacked. Images and colors paste one at a time.")
                .font(DesignTokens.rounded(10))
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    /// Default hint row when there's no batch selection.
    private var hintsBody: some View {
        HStack(spacing: 14) {
            Hint(icon: "arrow.up.arrow.down", label: "Switch Focus")
            Hint(icon: "arrow.left.and.right", label: "Navigate")
            Hint(icon: "return", label: "Paste")
            Hint(text: "space", label: "Preview")
            Hint(text: "⌥1-9", label: "Quick Paste")
            Spacer()
            Hint(icon: "escape", label: "Close")
        }
        .font(DesignTokens.rounded(10, weight: .medium))
        .foregroundStyle(DesignTokens.TextColor.tertiary)
    }

    /// Shown when 2+ cards are in the multi-selection. Surfaces the
    /// actions available on the stack so users don't have to guess.
    private var multiSelectBody: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text("\(state.selectionOrder.count) selected")
                    .font(DesignTokens.rounded(10, weight: .semibold))
                    .foregroundStyle(DesignTokens.TextColor.primary)
            }
            Hint(icon: "return", label: "Paste Stack")
            Hint(icon: "delete.left", label: "Delete")
            Hint(text: "⌘A", label: "Select All")
            Hint(icon: "escape", label: "Clear")
            Spacer()
            Button {
                state.clearMultiSelection()
            } label: {
                Text("Clear")
                    .font(DesignTokens.rounded(10, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .pointingHand()
        }
        .font(DesignTokens.rounded(10, weight: .medium))
        .foregroundStyle(DesignTokens.TextColor.tertiary)
    }

    private struct Hint: View {
        var icon: String? = nil
        var text: String? = nil
        let label: String
        var body: some View {
            HStack(spacing: 4) {
                Group {
                    if let icon {
                        Image(systemName: icon).font(.system(size: 9, weight: .semibold))
                    } else if let text {
                        Text(text).font(DesignTokens.rounded(9, weight: .semibold))
                    }
                }
                .foregroundStyle(DesignTokens.TextColor.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                Text(label)
            }
        }
    }
}

// MARK: - Accessibility permission banner

private struct AccessibilityBanner: View {
    @Environment(AppState.self) private var state
    @Default(.accentColorHex) private var accentHex

    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("Accessibility permission is required")
                    .font(DesignTokens.rounded(12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Paste into other apps won't work until Clipo is enabled in System Settings.")
                    .font(DesignTokens.rounded(10.5))
                    .foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
            Button {
                Accessibility.openSystemSettings()
            } label: {
                Text("Open Settings")
                    .font(DesignTokens.rounded(11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.22))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .pointingHand()

            Button {
                state.recheckAccessibility()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Re-check permission")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.inputRadius, style: .continuous)
                .fill(
                    // Accent solid with a subtle diagonal highlight overlay
                    // so the banner feels alive without depending on a
                    // hard-coded orange palette. Follows the user's theme.
                    LinearGradient(
                        colors: [accent, accent.opacity(0.82)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.0)],
                        startPoint: .top, endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.inputRadius, style: .continuous))
                    .allowsHitTesting(false)
                )
                .shadow(color: accent.opacity(0.30), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Cursor helper

extension View {
    func pointingHand() -> some View {
        self.onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
