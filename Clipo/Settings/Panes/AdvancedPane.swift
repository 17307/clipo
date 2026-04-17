import AppKit
import Defaults
import SwiftUI

struct AdvancedPane: View {
    @Default(.ignoreEvents) private var ignoreEvents
    @Default(.clearOnQuit) private var clearOnQuit
    @Default(.clearSystemClipboard) private var clearSystemClipboard

    @State private var accessibilityGranted: Bool = Accessibility.isTrusted(prompt: false)
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            Section("Monitoring") {
                Toggle("Pause clipboard monitoring", isOn: $ignoreEvents)
                Text("When paused, new copies are ignored and the menu bar icon is dimmed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("On quit") {
                Toggle("Clear clipboard history when quitting", isOn: $clearOnQuit)
                Toggle("Also clear the system clipboard", isOn: $clearSystemClipboard)
                    .disabled(!clearOnQuit)
            }

            Section("Accessibility") {
                HStack(spacing: 8) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Text(accessibilityGranted ? "Granted" : "Not granted")
                    Spacer()
                    Button("Open System Settings") { Accessibility.openSystemSettings() }
                    Button("Re-check") {
                        accessibilityGranted = Accessibility.isTrusted(prompt: false)
                    }
                }
                Text("Required to synthesize ⌘V and paste into other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Diagnostics") {
                pathRow(label: "Storage:", url: storageURL)
                pathRow(label: "Logs:", url: logsURL)
            }

            Section("Reset") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Text("Reset all settings…")
                }
                Text("Restores every Clipo preference to its default. History is not affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Reset all settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAll() }
        } message: {
            Text("All Clipo preferences will return to their defaults. Your clipboard history and Pinboards are kept.")
        }
        .onAppear {
            accessibilityGranted = Accessibility.isTrusted(prompt: false)
        }
    }

    private func pathRow(label: String, url: URL) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Text(url.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }

    private var storageURL: URL {
        URL.applicationSupportDirectory.appending(path: "Clipo/Storage.sqlite")
    }

    private var logsURL: URL {
        (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false))?
            .appending(path: "Logs/Clipo") ?? URL(fileURLWithPath: "/tmp")
    }

    private func resetAll() {
        Defaults.reset(
            .checkInterval, .maxHistorySize, .enabledPasteboardTypes,
            .ignoredPasteboardTypes, .ignoredApps, .ignoreAllAppsExceptListed,
            .ignoreRegexp, .ignoreEvents,
            .panelHeight, .panelBottomInset,
            .menuBarIcon, .accentColorHex, .showSourceIcon, .showFooterHints,
            .searchMode, .sortBy,
            .pasteByDefault, .removeFormattingByDefault,
            .clearSystemClipboard, .clearOnQuit
        )
    }
}
