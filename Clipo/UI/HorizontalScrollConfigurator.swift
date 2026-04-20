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

        // Smooth-scroll state — tracks the *remaining signed
        // displacement* the wheel still wants applied, and runs a
        // display-link tick that applies an exponential fraction of
        // it to the clip's current origin each frame. Velocity-style
        // (not target-style) so concurrent writers — SwiftUI's
        // `scrollTo` from click- or keyboard-driven selectedID
        // changes — compose additively with us instead of fighting.
        // See `queueDelta(_:)` and `tick(_:)`.
        private var displayLink: CADisplayLink?
        private var velocityRemaining: CGFloat = 0

        /// Points moved per wheel notch. NSScrollView's native wheel
        /// handling for precise deltas uses ~1 pt per point, and classic
        /// wheels emit ±1 per detent; 38 pt lines up with roughly one
        /// third of a card and matches the cadence users expect from
        /// macOS wheel scrolling elsewhere.
        private static let pointsPerNotch: CGFloat = 38
        /// Per-frame easing factor. Each tick applies this fraction of
        /// the remaining displacement to the clip and subtracts the
        /// same fraction from the pending total — exponential
        /// ease-out. 0.22 at 60 Hz reaches 99 % in ~18 frames
        /// (≈300 ms) for a single notch; consecutive notches add to
        /// the remaining velocity and the animation glides cleanly
        /// through them.
        private static let easing: CGFloat = 0.22
        /// Stop the display link when remaining displacement drops
        /// below this — avoids forever-ticking sub-pixel approach.
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

        /// Instant wheel handling for "Reduce motion" users — writes
        /// the clip origin directly, no display link, no easing. Also
        /// zeroes any pending smooth-scroll velocity so a reduce-
        /// motion snap isn't followed by a residual glide.
        private func snapScroll(by dx: CGFloat, on sv: NSScrollView) {
            guard let doc = sv.documentView else { return }
            let clip = sv.contentView
            let maxX = max(doc.frame.width - clip.bounds.width, 0)
            var origin = clip.bounds.origin
            origin.x = min(max(origin.x - dx, 0), maxX)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clip.scroll(to: origin)
            sv.reflectScrolledClipView(clip)
            CATransaction.commit()
            velocityRemaining = 0
            stopDisplayLink()
        }

        /// Append a wheel-tick delta to the pending remaining
        /// displacement and make sure the display link is running.
        /// Consecutive notches accumulate; a notch in the opposite
        /// direction partially cancels pending motion, which is the
        /// desired "I changed my mind" behaviour.
        private func queueDelta(_ dx: CGFloat) {
            velocityRemaining -= dx
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
            guard let sv = configured, let doc = sv.documentView else {
                stopDisplayLink()
                return
            }
            if abs(velocityRemaining) < Self.epsilon {
                velocityRemaining = 0
                stopDisplayLink()
                return
            }
            let clip = sv.contentView
            let maxX = max(doc.frame.width - clip.bounds.width, 0)
            // Apply a fraction of the remaining signed displacement
            // to the clip's *current* origin and subtract the same
            // fraction from the pending total. Composes additively
            // with any other writer on clip.bounds.origin.
            let step = velocityRemaining * Self.easing
            velocityRemaining -= step
            var origin = clip.bounds.origin
            let proposedX = origin.x + step
            let clampedX = min(max(proposedX, 0), maxX)
            origin.x = clampedX
            // If the step would have pushed past a boundary, drop
            // the remaining velocity to zero. Without this, a user
            // who wheels hard while already at an edge accumulates
            // velocity pointing into the wall; it then takes several
            // opposite-direction wheel notches to overcome the
            // residue before visible motion resumes, which feels
            // like broken input.
            if clampedX != proposedX {
                velocityRemaining = 0
            }
            // Disable implicit CA actions on the bounds change.
            // Without this each tick's scroll(to:) spawns a default
            // ~0.25 s layer animation that's instantly replaced by
            // the next tick's — the visual overlap of those
            // in-flight mini-animations reads as jitter on every
            // wheel scroll, most visibly on the first tick.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clip.scroll(to: origin)
            sv.reflectScrolledClipView(clip)
            CATransaction.commit()
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
