import AppKit
import SwiftUI

/// Reports click counts without SwiftUI's gesture-disambiguation delay.
/// On every `mouseDown`, the handler is invoked with `(clickCount, modifiers)`:
/// - First click of a double-click fires `onClick(1, mods)` immediately.
/// - Second click fires `onClick(2, mods)` immediately.
/// - `modifiers` lets the caller branch on ⌘/⇧ for multi-select behavior.
/// Because paste closes the panel, the transient single-click behavior
/// during a double-click isn't observable by the user.
///
/// Right-click is NOT intercepted — overriding rightMouseDown and calling
/// super made SwiftUI's .contextMenu underneath wait a visible beat
/// before opening. The right-click vs multi-selection UX is instead
/// handled by the context menu builder itself re-checking membership.
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

    override func mouseDown(with event: NSEvent) {
        onClick(event.clickCount, event.modifierFlags)
    }
}
