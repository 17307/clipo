import AppKit
import SwiftUI

/// Bridge view that reaches up to the enclosing NSScrollView and patches
/// two gaps in SwiftUI's horizontal ScrollView on macOS:
///
///   1. Force `scrollerStyle = .overlay` + disable both scrollers. SwiftUI's
///      `.scrollIndicators(.hidden)` is silently ignored when System
///      Settings → Appearance → "Show scroll bars" is "Always" — the mode
///      macOS flips to the moment a USB mouse is plugged in. Without this
///      override a legacy scrollbar stamps itself across the bottom of the
///      card row.
///
///   2. Translate classic-mouse vertical-wheel deltas into horizontal
///      scrolling. NSScrollView does not do this for a horizontal-only
///      scroll view. Trackpads and Magic Mouse already emit precise
///      scrolling deltas (including a horizontal axis) so those are passed
///      through untouched and detected via `hasPreciseScrollingDeltas`.
struct HorizontalScrollConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> Bridge { Bridge() }
    func updateNSView(_ nsView: Bridge, context: Context) {}

    final class Bridge: NSView {
        private var monitor: Any?
        private weak var configured: NSScrollView?

        deinit { removeMonitor() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
                configured = nil
                return
            }
            // SwiftUI may still be wiring up its NSScrollView when this
            // callback fires on first mount — defer a runloop tick so
            // `enclosingScrollView` has something to return.
            DispatchQueue.main.async { [weak self] in
                self?.attach()
            }
        }

        private func attach() {
            guard let sv = enclosingScrollView, sv !== configured else { return }
            removeMonitor()
            configured = sv

            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.hasHorizontalScroller = false
            sv.hasVerticalScroller = false
            sv.verticalScrollElasticity = .none

            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let sv = self.configured else { return event }
                guard let eventWindow = event.window,
                      eventWindow === sv.window else {
                    return event
                }
                // Trackpads and Magic Mouse report precise deltas and
                // already scroll horizontally on their own — leave them
                // alone. We only step in for classic wheels, which emit
                // coarse ±1 ticks on deltaY.
                if event.hasPreciseScrollingDeltas { return event }
                if event.scrollingDeltaY == 0 { return event }
                // Scope the interception to the carousel itself so we
                // don't silently break wheel scrolling anywhere else in
                // the same window.
                let local = sv.convert(event.locationInWindow, from: nil)
                guard sv.bounds.contains(local) else { return event }

                let clip = sv.contentView
                guard let doc = sv.documentView else { return event }
                // ~40 pt per wheel notch lines up roughly with one third
                // of a card width — matches trackpad two-finger cadence.
                let step: CGFloat = 40
                let dx = event.scrollingDeltaY * step
                var origin = clip.bounds.origin
                let maxX = max(doc.frame.width - clip.bounds.width, 0)
                origin.x = min(max(origin.x - dx, 0), maxX)
                clip.scroll(to: origin)
                sv.reflectScrolledClipView(clip)
                return nil
            }
        }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}
