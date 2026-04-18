import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Global — registered via KeyboardShortcuts.onKeyDown so the panel
    // starts sliding the instant the combo is pressed, not when it's released.
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.command, .shift]))

    // Window-local — NOT registered with onKeyDown. KeyboardShortcuts is
    // used here only for storage + the Recorder UI. BottomPanel.sendEvent
    // matches incoming events against the stored value and acts only while
    // the panel is key. This is critical: registering a plain key (e.g. ⌫)
    // with KeyboardShortcuts globally would eat that keystroke SYSTEM-WIDE.

    /// Write the selected item back to the clipboard without pasting. Default ⌥⏎.
    static let copyAgain = Self("copyAgain", default: .init(.return, modifiers: [.option]))
    /// Paste the selected item, forcibly stripping formatting. Default ⇧⏎.
    static let pastePlain = Self("pastePlain", default: .init(.return, modifiers: [.shift]))
    /// Paste the selected item, forcibly keeping original formatting. Default ⌥⇧⏎.
    static let pasteFormatted = Self("pasteFormatted", default: .init(.return, modifiers: [.option, .shift]))
}
