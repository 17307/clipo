import AppKit
import SwiftUI

/// Reports click counts without SwiftUI's gesture-disambiguation delay.
/// On every `mouseDown`, the handler is invoked with `(clickCount, modifiers)`:
/// - First click of a double-click fires `onClick(1, mods)` immediately.
/// - Second click fires `onClick(2, mods)` immediately.
/// - `modifiers` lets the caller branch on ⌘/⇧ for multi-select behavior.
/// Because paste closes the panel, the transient single-click behavior
/// during a double-click isn't observable by the user.
struct ClickCatcher: NSViewRepresentable {
    let onClick: (Int, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        ClickCatcherNSView(onClick: onClick)
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ClickCatcherNSView)?.onClick = onClick
    }
}

private final class ClickCatcherNSView: NSView {
    var onClick: (Int, NSEvent.ModifierFlags) -> Void

    init(onClick: @escaping (Int, NSEvent.ModifierFlags) -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Only intercept left-click; let right-click pass through to the SwiftUI
    // context menu underneath.
    override func mouseDown(with event: NSEvent) {
        onClick(event.clickCount, event.modifierFlags)
    }
}
