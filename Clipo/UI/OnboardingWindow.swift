import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

/// A small centered welcome window shown once on first launch. Walks the
/// user through the two things that will otherwise cause confusion:
/// - Clipo is menu-bar only; there's no Dock icon
/// - Paste needs Accessibility permission or the hotkey produces a beep
final class OnboardingWindowController: NSWindowController {
    private static var shared: OnboardingWindowController?

    static func showIfNeeded() {
        guard !Defaults[.didShowOnboarding] else { return }
        show()
    }

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let content = OnboardingView { dismiss() }
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 480, height: 540))
        window.center()
        window.level = .floating
        let controller = OnboardingWindowController(window: window)
        window.delegate = controller
        shared = controller
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func dismiss() {
        Defaults[.didShowOnboarding] = true
        shared?.window?.close()
        shared = nil
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // User hit the red dot — still consider the onboarding done.
        Defaults[.didShowOnboarding] = true
        Self.shared = nil
    }
}

// MARK: - View

private struct OnboardingView: View {
    let onDismiss: () -> Void

    @State private var accessibilityGranted: Bool = Accessibility.isTrusted(prompt: false)
    @Default(.accentColorHex) private var accentHex
    private var accent: Color { Color(hex: accentHex) ?? DesignTokens.accent }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tip(
                        icon: "command",
                        title: "Open Clipo with \(toggleShortcutLabel)",
                        body: "That hotkey is the whole app — tap it any time to summon the carousel over your current window. Tap again or hit Esc to dismiss."
                    )
                    tip(
                        icon: "square.grid.2x2",
                        title: "Everything lives in the menu bar",
                        body: "No Dock icon by design — Clipo stays out of the way. Click the menu-bar icon for quick actions, or right-click for the full menu."
                    )
                    tipWithAccessory(
                        icon: "hand.tap",
                        title: "Accessibility permission enables Paste",
                        body: "Pressing Return on a card synthesises ⌘V into the previous app. macOS needs you to allow that in System Settings → Privacy & Security → Accessibility."
                    ) {
                        accessibilityPill
                    }
                    tip(
                        icon: "magnifyingglass",
                        title: "Search includes text inside images",
                        body: "Clipo runs on-device OCR against screenshots, so typing a word you saw in a screenshot finds the image too — fully local, never leaves your Mac."
                    )
                }
                .padding(22)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 480, height: 540)
        .background(.regularMaterial)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(accent)
                .padding(.top, 24)
            Text("Welcome to Clipo")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("A keyboard-first clipboard manager for macOS.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 18)
    }

    private func tip(
        icon: String,
        title: String,
        body: String
    ) -> some View {
        tipWithAccessory(icon: icon, title: title, body: body) { EmptyView() }
    }

    @ViewBuilder
    private func tipWithAccessory<Accessory: View>(
        icon: String,
        title: String,
        body: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory().padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var accessibilityPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(accessibilityGranted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(accessibilityGranted ? "Granted" : "Not granted yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            if !accessibilityGranted {
                Button("Open Settings") {
                    Accessibility.openSystemSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    accessibilityGranted = Accessibility.isTrusted(prompt: false)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Re-check")
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("You can revisit this in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Let's go") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .tint(accent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var toggleShortcutLabel: String {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description ?? "⇧⌘V"
    }
}
