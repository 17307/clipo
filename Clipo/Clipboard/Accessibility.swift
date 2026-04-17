import AppKit
import ApplicationServices

enum Accessibility {
    @discardableResult
    static func isTrusted(prompt: Bool = false) -> Bool {
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func check() {
        if !isTrusted() {
            openSystemSettings()
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
