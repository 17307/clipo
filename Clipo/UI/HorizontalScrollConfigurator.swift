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

        // Smooth-scroll state — accumulates wheel deltas into a target
        // offset and runs a display-link tick that eases the clip view
        // toward it, so classic-mouse scrolling doesn't feel like a
        // step function. See `queueDelta(_:)` and `tick(_:)`.
        private var displayLink: CADisplayLink?
        private var targetX: CGFloat = 0
        private var currentX: CGFloat = 0

        /// Points moved per wheel notch. NSScrollView's native wheel
        /// handling for precise deltas uses ~1 pt per point, and classic
        /// wheels emit ±1 per detent; 38 pt lines up with roughly one
        /// third of a card and matches the cadence users expect from
        /// macOS wheel scrolling elsewhere.
        private static let pointsPerNotch: CGFloat = 38
        /// Per-frame easing factor. Each tick closes this fraction of
        /// the remaining distance — so the motion is exponential
        /// ease-out. 0.22 at 60 Hz reaches 99 % in ~18 frames (≈300 ms)
        /// for a single notch; consecutive notches extend the target
        /// and the animation glides cleanly through them.
        private static let easing: CGFloat = 0.22
        /// Stop the display link when we're this close to the target —
        /// avoids forever-ticking sub-pixel approach.
        private static let epsilon: CGFloat = 0.5

        deinit {
            removeMonitor()
            stopDisplayLink()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
                stopDisplayLink()
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
            stopDisplayLink()
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

                let dx = event.scrollingDeltaY * Self.pointsPerNotch
                // Reduce motion: the user has asked the system to
                // skip decorative animation, so translate the wheel
                // tick into an immediate scroll rather than a smoothly
                // interpolated one.
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    self.snapScroll(by: dx, on: sv)
                    return nil
                }
                self.queueDelta(dx)
                return nil
            }
        }

        /// Instant wheel handling for "Reduce motion" users — same
        /// math as `queueDelta` but writes the clip origin directly,
        /// no display link, no easing.
        private func snapScroll(by dx: CGFloat, on sv: NSScrollView) {
            guard let doc = sv.documentView else { return }
            let clip = sv.contentView
            let maxX = max(doc.frame.width - clip.bounds.width, 0)
            var origin = clip.bounds.origin
            origin.x = min(max(origin.x - dx, 0), maxX)
            clip.scroll(to: origin)
            sv.reflectScrolledClipView(clip)
            // Keep cached state consistent in case a full-motion
            // wheel tick arrives later (e.g. user toggled the
            // preference mid-session).
            currentX = origin.x
            targetX = origin.x
        }

        /// Append a wheel-tick delta to the interpolation target and
        /// make sure the display link is running. If a smooth scroll is
        /// already in flight the delta stacks onto the existing target;
        /// if not, we seed `currentX` from the clip view so keyboard
        /// navigation or a SwiftUI `scrollTo` between bursts is taken
        /// as the new origin.
        private func queueDelta(_ dx: CGFloat) {
            guard let sv = configured, let doc = sv.documentView else { return }
            let clip = sv.contentView
            let maxX = max(doc.frame.width - clip.bounds.width, 0)
            if displayLink == nil {
                currentX = clip.bounds.origin.x
                targetX = currentX
            }
            targetX = min(max(targetX - dx, 0), maxX)
            startDisplayLink()
        }

        private func startDisplayLink() {
            guard displayLink == nil, let sv = configured else { return }
            // NSView.displayLink(target:selector:) is macOS 14+; the
            // project's deployment target is 14.0 so it's always
            // available. It auto-ticks at the display's refresh rate
            // (60 Hz / 120 Hz on ProMotion) which is exactly what we
            // want for per-frame interpolation.
            let link = sv.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .current, forMode: .common)
            displayLink = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            guard let sv = configured else {
                stopDisplayLink()
                return
            }
            let clip = sv.contentView
            // Resync against the clip's actual origin if something
            // external (SwiftUI `scrollTo` on keyboard nav, a
            // programmatic move, selectedID change) wrote to it
            // between our ticks. Treat external motion as an
            // interruption: our target is now stale and resuming our
            // animation would yank the clip backwards by the delta,
            // so cancel instead — the next wheel notch will re-seed
            // from the new origin naturally.
            if abs(clip.bounds.origin.x - currentX) > 1 {
                currentX = clip.bounds.origin.x
                targetX = currentX
                stopDisplayLink()
                return
            }
            let diff = targetX - currentX
            if abs(diff) < Self.epsilon {
                currentX = targetX
                apply(clip: clip, on: sv)
                stopDisplayLink()
                return
            }
            currentX += diff * Self.easing
            apply(clip: clip, on: sv)
        }

        private func apply(clip: NSClipView, on sv: NSScrollView) {
            var origin = clip.bounds.origin
            origin.x = currentX
            clip.setBoundsOrigin(origin)
            sv.reflectScrolledClipView(clip)
        }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
        }
    }
}
