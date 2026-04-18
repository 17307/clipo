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
/// `onRightClick` fires just before AppKit propagates the right-click to
/// the SwiftUI contextMenu below. It exists so carousel code can match
/// Finder's convention: right-clicking a card that isn't in the current
/// multi-selection should switch focus to that card before the menu
/// opens, instead of showing a single-item menu while a stale
/// multi-selection stays visibly highlighted.
struct ClickCatcher: NSViewRepresentable {
    let onClick: (Int, NSEvent.ModifierFlags) -> Void
    var onRightClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        ClickCatcherNSView(onClick: onClick, onRightClick: onRightClick)
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let v = view as? ClickCatcherNSView else { return }
        v.onClick = onClick
        v.onRightClick = onRightClick
    }
}

private final class ClickCatcherNSView: NSView {
    var onClick: (Int, NSEvent.ModifierFlags) -> Void
    var onRightClick: (() -> Void)?

    init(
        onClick: @escaping (Int, NSEvent.ModifierFlags) -> Void,
        onRightClick: (() -> Void)?
    ) {
        self.onClick = onClick
        self.onRightClick = onRightClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick(event.clickCount, event.modifierFlags)
    }

    override func rightMouseDown(with event: NSEvent) {
        // Adjust selection state first, then let the event bubble through
        // to AppKit so the SwiftUI .contextMenu underneath still fires.
        onRightClick?()
        super.rightMouseDown(with: event)
    }
}
