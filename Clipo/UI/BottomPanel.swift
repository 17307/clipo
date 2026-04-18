import AppKit
import Defaults
import SwiftUI

/// A borderless NSPanel anchored to the bottom edge of the active screen.
/// Inspired by Maccy's `FloatingPanel` (see /Users/ymoon/workspace/project/swift/Maccy/Maccy/FloatingPanel.swift).
final class BottomPanel<Content: View>: NSPanel, NSWindowDelegate {
    private let onClose: () -> Void
    private(set) var isPresented = false
    /// Set while a PreviewPanel is on top of us; suppresses auto-close on resignKey.
    var isShowingPreview = false

    init(onClose: @escaping () -> Void, @ViewBuilder view: () -> Content) {
        self.onClose = onClose

        let initialSize = NSSize(width: 1024, height: Defaults[.panelHeight])
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        delegate = self
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Inherit the system appearance so light ↔ dark mode works without
        // a restart. (Previously hard-coded to vibrantLight.)
        appearance = nil

        let host = NSHostingView(rootView: view())
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = DesignTokens.panelRadius
        container.layer?.masksToBounds = true
        // Only round top corners so the panel hugs the bottom screen edge flush.
        container.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Thin drag strip at the very top edge — lets the user grow or
        // shrink the panel by dragging. Sits on top of the SwiftUI content
        // so the cursor flips to resize when hovered.
        let resizeHandle = ResizeHandleView { [weak self] delta in
            self?.applyHeightDelta(delta)
        } onRelease: { [weak self] in
            self?.persistHeight()
        }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: container.topAnchor),
            resizeHandle.heightAnchor.constraint(equalToConstant: 10),
        ])

        contentView = container
    }

    // MARK: - Height drag

    /// In-flight drag delta accumulates here so we don't round-trip through
    /// Defaults (and SwiftData notifications) on every frame.
    private var dragHeight: CGFloat?

    fileprivate func applyHeightDelta(_ delta: CGFloat) {
        guard isPresented, let screen = screen else { return }
        // AppKit's locationInWindow.y grows as the mouse moves UP the
        // screen, so delta > 0 means the user is dragging the handle up.
        // Our panel is anchored to the bottom edge — moving the top edge
        // up grows the panel — so we ADD the delta, not subtract it. The
        // previous code inverted this and made drag direction feel wrong.
        let current = dragHeight ?? frame.height
        let proposed = (current + delta)
            .clamped(to: panelMinHeight...panelMaxHeight)
        dragHeight = proposed
        let visibleFrame = screen.visibleFrame
        let bottomInset = Defaults[.panelBottomInset]
        let newFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY + bottomInset,
            width: visibleFrame.width,
            height: proposed
        )
        setFrame(newFrame, display: true)
    }

    fileprivate func persistHeight() {
        if let h = dragHeight {
            Defaults[.panelHeight] = Double(h)
        }
        dragHeight = nil
    }

    func toggle() {
        isPresented ? close() : open()
    }

    /// Force SwiftUI to resolve its initial layout at launch instead of
    /// during the first hotkey press. Without this the very first ⇧⌘V
    /// visibly stalls ~40-80ms before the slide animation kicks in, while
    /// the NSHostingView measures the carousel, cards, and tabs for the
    /// first time. Done via an alpha=0 order-in far off-screen — nothing
    /// ever reaches the user's eyes.
    func prewarm() {
        let targetScreen = NSScreen.forMouse() ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen else { return }
        let size = NSSize(
            width: targetScreen.visibleFrame.width,
            height: Defaults[.panelHeight]
        )
        let offscreen = NSRect(
            x: targetScreen.visibleFrame.minX,
            y: targetScreen.visibleFrame.minY - size.height - 200,
            width: size.width,
            height: size.height
        )
        let savedAlpha = alphaValue
        alphaValue = 0
        setFrame(offscreen, display: false)
        orderBack(nil)
        contentView?.layoutSubtreeIfNeeded()
        contentView?.displayIfNeeded()
        orderOut(nil)
        alphaValue = savedAlpha
    }

    /// Called by AppDelegate when screens are added/removed/reconfigured
    /// (e.g. the user unplugs the external display the panel was anchored
    /// to). Re-anchors the panel to the screen where the mouse currently
    /// lives, or silently closes if no screen is available.
    func repositionForCurrentScreen() {
        guard isPresented else { return }
        guard let screen = NSScreen.forMouse() else {
            close()
            return
        }
        let visibleFrame = screen.visibleFrame
        let height = Defaults[.panelHeight]
        let bottomInset = Defaults[.panelBottomInset]
        let newFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY + bottomInset,
            width: visibleFrame.width,
            height: height
        )
        // No animation — the screen change itself is jarring enough; snapping
        // into place is more trustworthy than a second slide.
        setFrame(newFrame, display: true)
    }

    func open() {
        guard let screen = NSScreen.forMouse() else { return }
        let visibleFrame = screen.visibleFrame

        // Full screen width, edge-to-edge.
        let width = visibleFrame.width
        let height = Defaults[.panelHeight]
        let bottomInset = Defaults[.panelBottomInset]

        let finalFrame = NSRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY + bottomInset,
            width: width,
            height: height
        )

        // Start below the screen and slide up.
        let startFrame = NSRect(
            x: finalFrame.minX,
            y: visibleFrame.minY - height,
            width: width,
            height: height
        )
        setFrame(startFrame, display: false)
        orderFrontRegardless()
        makeKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(finalFrame, display: true)
        }
        isPresented = true
    }

    /// Intercept Return/Escape before they reach any SwiftUI text field.
    /// `sendEvent` fires for every event routed to this window; returning early
    /// without calling `super` consumes the event.
    override func sendEvent(_ event: NSEvent) {
        if isPresented, event.type == .keyDown {
            // Window-local configurable shortcuts (Copy Again / Paste
            // variants). Match first — they may use ⇧⏎ / ⌥⏎ which would
            // otherwise fall into the plain Return branch below.
            let handled = MainActor.assumeIsolated {
                AppState.shared.appDelegate?.handleWindowLocalShortcut(event) ?? false
            }
            if handled { return }

            // ⌥1–⌥9 → quick paste the Nth visible card, regardless of
            // whether the search field, the carousel, or neither has focus.
            if event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               let digit = Int(chars), digit >= 1, digit <= 9 {
                MainActor.assumeIsolated {
                    AppState.shared.selectByIndex(digit - 1)
                    AppState.shared.pasteSelected()
                }
                return
            }
            switch event.keyCode {
            case 36, 76:  // Return / numpad Enter
                MainActor.assumeIsolated {
                    AppState.shared.pasteSelected()
                }
                return
            case 53:  // Escape
                MainActor.assumeIsolated {
                    // First Escape clears a multi-selection without closing
                    // the panel; a second press (nothing selected) closes.
                    if AppState.shared.isMultiSelecting {
                        AppState.shared.clearMultiSelection()
                    } else {
                        self.close()
                    }
                }
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    override func close() {
        guard isPresented else {
            super.close()
            return
        }
        // Close instantly (no animation) so the previously-active app regains
        // keyboard focus immediately. This is required for CGEvent ⌘V paste
        // to land in the target app rather than our now-closing panel.
        isPresented = false
        super.close()
        onClose()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // Auto-close when the user clicks somewhere else — but don't close
        // if we only lost key because our own PreviewPanel just took it.
        if isPresented && !isShowingPreview {
            close()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

private extension NSScreen {
    static func forMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? .main
    }
}

/// Min/max panel heights. Below 280 the footer+search+one row of cards
/// stops fitting; above 640 it eats most of the screen. Top-level because
/// generic types can't have static stored properties.
private let panelMinHeight: CGFloat = 280
private let panelMaxHeight: CGFloat = 640

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

/// Thin 6 pt strip across the top of the panel with a centered 3-dot
/// grab indicator. Flips the cursor to resize-up-down when hovered and
/// reports vertical drag deltas to the containing panel. The dot row is
/// what turns "you can totally resize the panel" from invisible magic
/// into a discoverable affordance.
private final class ResizeHandleView: NSView {
    let onDrag: (CGFloat) -> Void
    let onRelease: () -> Void
    private var lastDragY: CGFloat?

    init(onDrag: @escaping (CGFloat) -> Void,
         onRelease: @escaping () -> Void) {
        self.onDrag = onDrag
        self.onRelease = onRelease
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 3 small dots, centered. Uses tertiaryLabel so it auto-adapts to
        // both light and dark mode at a low-but-visible contrast level.
        let dotSize: CGFloat = 3
        let spacing: CGFloat = 4
        let totalWidth = dotSize * 3 + spacing * 2
        let startX = (bounds.width - totalWidth) / 2
        let y = (bounds.height - dotSize) / 2
        NSColor.tertiaryLabelColor.setFill()
        for i in 0..<3 {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotSize, height: dotSize))
            path.fill()
        }
    }

    override func resetCursorRects() {
        // Entire handle shows the resize cursor.
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragY = event.locationInWindow.y
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragY else { return }
        let y = event.locationInWindow.y
        let delta = y - last
        lastDragY = y
        onDrag(delta)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragY = nil
        onRelease()
    }
}
