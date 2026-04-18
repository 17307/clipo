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
        contentView = container
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
