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
        IPCServer.shared.start()
        warmSourceAppIconCache()
        setupScreenChangeObserver()

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

    /// Briefly replace the menu bar icon with a checkmark so a just-fired
    /// paste/copy gets silent visual confirmation even though the panel is
    /// already gone by the time the user looks up. ~220ms is long enough to
    /// register in peripheral vision and short enough to feel incidental.
    private var statusFlashToken: UUID?
    func flashStatusIcon() {
        guard let button = statusItem.button else { return }
        let token = UUID()
        statusFlashToken = token
        let flash = NSImage(systemSymbolName: "checkmark.circle.fill",
                            accessibilityDescription: "Pasted")
        flash?.isTemplate = true
        button.image = flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.statusFlashToken == token else { return }
            button.image = self.currentStatusIcon()
            self.statusFlashToken = nil
        }
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

        let show = menu.addItem(withTitle: "Show Clipo", action: #selector(openFromMenu), keyEquivalent: "")
        show.setShortcut(for: .togglePanel)
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
        // Only togglePanel is truly global — the others are window-local and
        // matched inside BottomPanel.sendEvent so they don't eat keystrokes
        // system-wide (which would break e.g. the ⌫ key in other apps).
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Called by BottomPanel.sendEvent for every keyDown. Returns true if
    /// the event matched one of our window-local shortcuts and was handled.
    func handleWindowLocalShortcut(_ event: NSEvent) -> Bool {
        guard let panel, panel.isPresented else { return false }
        guard let incoming = KeyboardShortcuts.Shortcut(event: event) else { return false }
        guard let item = AppState.shared.selectedItem ?? AppState.shared.items.first else {
            return false
        }
        if incoming == KeyboardShortcuts.getShortcut(for: .copyAgain) {
            AppState.shared.copyAgain(item)
            return true
        }
        if incoming == KeyboardShortcuts.getShortcut(for: .pastePlain) {
            AppState.shared.pasteAsPlainText(item)
            return true
        }
        if incoming == KeyboardShortcuts.getShortcut(for: .pasteFormatted) {
            AppState.shared.pasteWithFormatting(item)
            return true
        }
        return false
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
            // Batch all state mutations inside one transaction so SwiftUI
            // observes them as a single atomic change and doesn't try to
            // interpolate between intermediate values while the panel is
            // mid-slide. applyFilter() already suppresses its own inner
            // animations; we extend that suppression to the surrounding
            // selection/openToken/accessibility writes.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                AppState.shared.searchQuery = ""
                AppState.shared.recheckAccessibility()
                AppState.shared.isOptionDown = NSEvent.modifierFlags.contains(.option)
                // applyFilter repoints selectedID to items.first if the
                // previous selection fell out of the visible set, so no
                // redundant selectedID write needed here.
                AppState.shared.applyFilter()
                AppState.shared.openToken = UUID()
            }
            panel.open()
            // NB: no defensive reload() here. The engine already keeps
            // allItems fresh via add(), and every mutation path
            // (delete/clearAll/move/pinboard CRUD) calls reload() itself —
            // a Task { reload() } here would just re-publish items into
            // the middle of the slide animation and cause a ForEach churn.
        }
    }

    func closePanel() {
        panel?.close()
    }

    /// Exposed for IPC consumers (e.g. `clipocli health`).
    var panelIsPresented: Bool { panel?.isPresented == true }

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
        // Scripts only operate on textual input. Give a specific message per
        // kind so the user knows why a particular item can't be transformed.
        switch item.primaryKind {
        case .image:
            showScriptAlert(title: "\(script.name): cannot run on an image",
                            message: "Scripts transform text. This item is an image.")
            return
        case .file:
            showScriptAlert(title: "\(script.name): cannot run on a file item",
                            message: "Scripts transform text. This item contains file references.")
            return
        default: break
        }
        guard let input = item.text, !input.isEmpty else {
            showScriptAlert(title: "\(script.name): no text to transform",
                            message: "This script needs non-empty text as input.")
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

    /// Called by PreviewPanel when it lost key to some other window without
    /// an explicit close() call. We only close the main panel if focus went
    /// to a genuinely external window; a nil / transitional keyWindow or
    /// our own main panel both keep main open (defaults to "safe").
    func previewLostFocus() {
        let newKey = NSApp.keyWindow
        let isExternal = newKey != nil
            && newKey !== panel
            && newKey !== previewPanel
        previewPanel?.close()
        if isExternal {
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

    // MARK: - Icon cache warmup

    /// LaunchServices lookups (`NSWorkspace.urlForApplication(withBundleIdentifier:)`)
    /// are fast once resolved but can stall the main thread 20–100ms on the
    /// very first call for a given bundle id. Pre-warming the cache off-main
    /// at launch means the first panel open is icon-populated from frame one.
    private func warmSourceAppIconCache() {
        let bundleIDs = Set(AppState.shared.items.compactMap(\.sourceAppBundleID))
        guard !bundleIDs.isEmpty else { return }
        Task.detached(priority: .utility) {
            for id in bundleIDs {
                _ = AppIconCache.icon(forBundleID: id, size: 20)
            }
        }
    }

    // MARK: - Screen change

    /// If the user unplugs the display the panel is pinned to, the panel can
    /// end up on a frame that no longer exists (invisible, dead). Listen for
    /// screen reconfigurations and re-anchor to whatever screen the mouse is
    /// currently over.
    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The notification is delivered on the main queue, but the
            // closure signature is Sendable — hop via MainActor to satisfy
            // the compiler that `panel` access is isolated.
            Task { @MainActor in self?.panel?.repositionForCurrentScreen() }
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

        // Re-evaluate the visible list when the user switches search mode
        // (exact / contains / fuzzy). In-memory only — no DB round-trip.
        Task { [weak self] in
            for await _ in Defaults.updates(.searchMode, initial: false) {
                guard self != nil else { return }
                AppState.shared.applyFilter()
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
