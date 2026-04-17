import AppKit
import SwiftUI

/// An NSTextView-backed read-only text view for preview. NSTextView uses lazy
/// layout via NSLayoutManager so multi-megabyte strings scroll smoothly
/// without locking the main thread the way a SwiftUI `Text` would.
struct ScrollableTextView: NSViewRepresentable {
    let text: String
    var font: NSFont = .systemFont(ofSize: 13, weight: .regular)
    var insets: NSSize = NSSize(width: 18, height: 14)

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.isEditable = false
        tv.isSelectable = true
        tv.isAutomaticLinkDetectionEnabled = true
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = insets
        tv.font = font
        tv.textColor = .labelColor
        tv.string = ""

        // Allow horizontal growth so long lines wrap at the viewport width.
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.font != font { tv.font = font }
        if tv.string != text { tv.string = text }
    }
}
