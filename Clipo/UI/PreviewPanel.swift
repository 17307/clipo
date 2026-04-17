import AppKit
import SwiftUI

/// A centered quick-look-style preview panel. Becomes key so users can
/// select text and use ⌘C / ⌘A; dismiss & navigation keys without modifiers
/// are intercepted here, everything else (⌘+anything, text editing) falls
/// through to the SwiftUI first responder.
final class PreviewPanel: NSPanel {
    private let onClose: () -> Void
    private var isClosing = false

    init<Content: View>(onClose: @escaping () -> Void, @ViewBuilder view: () -> Content) {
        self.onClose = onClose

        let size = NSSize(width: 720, height: 540)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        appearance = NSAppearance(named: .vibrantLight)

        let host = NSHostingView(rootView: view())
        host.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 22
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.black.withAlphaComponent(0.16).cgColor
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            // Plain key (no modifiers) — intercept dismissal / navigation.
            switch event.keyCode {
            case 49, 53:  // space, escape → close preview
                MainActor.assumeIsolated { self.close() }
                return
            case 123:  // left → prev card + close
                MainActor.assumeIsolated {
                    AppState.shared.selectPrevious()
                    self.close()
                }
                return
            case 124:  // right → next card + close
                MainActor.assumeIsolated {
                    AppState.shared.selectNext()
                    self.close()
                }
                return
            default:
                break
            }
        }
        // Everything else (typing into text fields, ⌘C copy, ⌘A select-all,
        // arrow keys with modifiers, etc.) flows through to the responder chain.
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        // We only hit this when a DIFFERENT window took key away from us,
        // not during our own close(). AppDelegate decides whether to keep
        // the main panel open (click landed on it) or close everything.
        guard !isClosing else { return }
        MainActor.assumeIsolated {
            AppState.shared.appDelegate?.previewLostFocus()
        }
    }

    func open() {
        let targetScreen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main
        guard let screen = targetScreen else { return }

        let visible = screen.visibleFrame
        let size = NSSize(width: 720, height: 540)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        alphaValue = 1
        setFrame(NSRect(origin: origin, size: size), display: true)
        orderFrontRegardless()
        makeKey()
    }

    override func close() {
        guard !isClosing else { return }
        isClosing = true
        super.close()
        onClose()
    }
}
