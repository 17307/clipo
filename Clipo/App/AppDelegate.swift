import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: BottomPanel<AnyView>?
    private var previewPanel: PreviewPanel?
    private var settingsController: ClipoSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.appDelegate = self

        setupStatusBar()
        setupClipboard()
        setupHotkey()
        setupPanel()
        setupDefaultsObservers()
        setupModifierTracking()
        BuiltInScripts.installIfNeeded()
        AppState.shared.refreshScripts()
        AppState.shared.installDefaultPinboardsIfNeeded()

        // Prompt for Accessibility permission (required for CGEvent paste) on first launch.
        if !Accessibility.isTrusted(prompt: false) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                _ = Accessibility.isTrusted(prompt: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if Defaults[.clearOnQuit] {
            Task { @MainActor in AppState.shared.clearAll() }
        }
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = currentStatusIcon()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.appearsDisabled = Defaults[.ignoreEvents]
        }
    }

    private func currentStatusIcon() -> NSImage? {
        let name = Defaults[.menuBarIcon].rawValue
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Clipo")
        image?.isTemplate = true
        return image
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick =
            event?.type == .rightMouseUp ||
            event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showStatusMenu(from: sender)
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu(from button: NSStatusBarButton) {
        let menu = makeMenu()
        let point = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let show = menu.addItem(withTitle: "Show Clipo", action: #selector(openFromMenu), keyEquivalent: "v")
        show.keyEquivalentModifierMask = [.command, .shift]
        show.target = self

        menu.addItem(.separator())

        let settings = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self

        let clear = menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self

        menu.addItem(.separator())

        let quit = menu.addItem(withTitle: "Quit Clipo", action: #selector(quitApp), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self

        return menu
    }

    @objc private func openFromMenu() { togglePanel() }

    @objc private func clearHistory() {
        AppState.shared.clearAll()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func openSettings() {
        if settingsController == nil {
            settingsController = ClipoSettingsWindowController()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.show()
    }

    // MARK: - Clipboard monitor

    private func setupClipboard() {
        let engine = ClipboardEngine.shared
        engine.onNewCopy { item in
            Task { @MainActor in AppState.shared.add(item) }
        }
        engine.start()
    }

    // MARK: - Global hotkey

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        panel = BottomPanel(onClose: { [weak self] in
            // When the main panel closes for any reason, dismiss any open preview too.
            self?.previewPanel?.close()
            self?.previewPanel = nil
        }) {
            AnyView(
                RootView()
                    .environment(AppState.shared)
            )
        }
    }

    func togglePanel() {
        guard let panel else { return }
        if panel.isPresented {
            panel.close()
        } else {
            AppState.shared.searchQuery = ""
            AppState.shared.refresh()
            // Always start focused on the first card, regardless of what was
            // selected when the panel last closed.
            AppState.shared.selectedID = AppState.shared.items.first?.id
            AppState.shared.openToken = UUID()
            AppState.shared.recheckAccessibility()
            panel.open()
        }
    }

    func closePanel() {
        panel?.close()
    }

    // MARK: - Preview panel

    func showPreview(item: ClipItem) {
        previewPanel?.close()
        previewPanel = nil

        panel?.isShowingPreview = true

        let newPanel = PreviewPanel(onClose: { [weak self] in
            self?.handlePreviewClosed()
        }) {
            ClipPreviewView(item: item, onClose: { [weak self] in
                self?.previewPanel?.close()
            })
            .environment(AppState.shared)
        }
        previewPanel = newPanel
        newPanel.open()
    }

    func closePreview() {
        previewPanel?.close()
    }

    // MARK: - Scripts

    func runScript(_ script: ClipoScript, on item: ClipItem) {
        guard let input = item.text, !input.isEmpty else {
            showScriptAlert(title: "\(script.name): no text to transform",
                            message: "This script needs a text item as input.")
            return
        }
        switch ScriptEngine.run(script, input: input) {
        case .success(let output):
            // 1. Auto-copy the result to the system clipboard.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(output, forType: .string)

            // 2. Build a transient ClipItem so the existing preview view
            //    can render the result without persisting a duplicate.
            let transient = ClipItem(contents: [
                ClipContent(type: NSPasteboard.PasteboardType.string.rawValue,
                            value: output.data(using: .utf8))
            ])
            transient.title = output.shortened(to: 1_000)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            transient.sourceAppBundleID = nil

            // 3. Show the result preview (replaces any open preview).
            showPreview(item: transient)

        case .failure(let error):
            showScriptAlert(title: "\(script.name) failed",
                            message: error.localizedDescription)
        }
    }

    private func showScriptAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Called by PreviewPanel when it lost key to some other window without an
    /// explicit close() call. If the new key is our main panel (user clicked
    /// a card), keep main open. Otherwise the user clicked outside Clipo
    /// entirely — dismiss both windows.
    func previewLostFocus() {
        let clickedMain = (NSApp.keyWindow === panel)
        previewPanel?.close()
        if !clickedMain {
            panel?.close()
        }
    }

    private func handlePreviewClosed() {
        previewPanel = nil
        panel?.isShowingPreview = false
        if panel?.isPresented == true {
            // Re-assert SwiftUI focus on the carousel (the preview may have
            // taken keyboard focus while open).
            AppState.shared.openToken = UUID()
            panel?.makeKey()
        }
    }

    // MARK: - Modifier tracking (for ⌥N quick-paste badges)

    private func setupModifierTracking() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let down = event.modifierFlags.contains(.option)
            Task { @MainActor in AppState.shared.isOptionDown = down }
            return event
        }
    }

    // MARK: - Defaults → side-effect wiring

    private func setupDefaultsObservers() {
        // Restart the polling timer when the check interval changes.
        Task { [weak self] in
            for await _ in Defaults.updates(.checkInterval, initial: false) {
                guard self != nil else { return }
                ClipboardEngine.shared.restart()
            }
        }

        // Refresh the carousel when sort order changes.
        Task { [weak self] in
            for await _ in Defaults.updates(.sortBy, initial: false) {
                guard self != nil else { return }
                AppState.shared.refresh()
            }
        }

        // Drop the compiled-regex cache when the user edits patterns.
        Task { [weak self] in
            for await _ in Defaults.updates(.ignoreRegexp, initial: false) {
                guard self != nil else { return }
                ClipboardEngine.shared.invalidateRegexCache()
            }
        }

        // Swap the menu bar icon live.
        Task { [weak self] in
            for await _ in Defaults.updates(.menuBarIcon, initial: false) {
                guard let self else { return }
                self.statusItem.button?.image = self.currentStatusIcon()
            }
        }

        // Gray the menu bar icon when monitoring is paused.
        Task { [weak self] in
            for await value in Defaults.updates(.ignoreEvents, initial: false) {
                guard let self else { return }
                self.statusItem.button?.appearsDisabled = value
            }
        }

        // Trim history when the user lowers the size limit.
        Task { [weak self] in
            for await _ in Defaults.updates(.maxHistorySize, initial: false) {
                guard self != nil else { return }
                AppState.shared.enforceHistoryLimitNow()
            }
        }
    }
}
