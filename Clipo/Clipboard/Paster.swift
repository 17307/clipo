import AppKit
import CoreGraphics

/// Simulates ⌘V keystroke to paste the current pasteboard into the frontmost app.
/// Ported from Maccy's `Clipboard.paste()` — see `Maccy/Clipboard.swift:111-138`
/// in https://github.com/p0deje/Maccy.
enum Paster {
    private static let vKey: CGKeyCode = 0x09 // ANSI-V

    static func paste() {
        if !Accessibility.isTrusted(prompt: false) {
            // Without Accessibility permission, CGEvent posts are silently
            // dropped by the system. Ask explicitly and bail out.
            Task { @MainActor in showPermissionAlert() }
            return
        }

        let cmdFlag: CGEventFlags = .maskCommand
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyDown?.flags = cmdFlag
        keyUp?.flags = cmdFlag
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }

    @MainActor
    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Clipo needs Accessibility permission"
        alert.informativeText = """
            To paste into other apps, Clipo must post ⌘V on your behalf. \
            Open System Settings → Privacy & Security → Accessibility and \
            enable Clipo.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Accessibility.openSystemSettings()
        }
    }
}
