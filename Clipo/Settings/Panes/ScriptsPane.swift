import AppKit
import Defaults
import SwiftUI

struct ScriptsPane: View {
    @Default(.disabledScriptIDs) private var disabled
    @State private var scripts: [ClipoScript] = AppState.shared.scripts.isEmpty
        ? ScriptLoader.loadAll()
        : AppState.shared.scripts
    @State private var showDocs = false

    var body: some View {
        Form {
            Section {
                if scripts.isEmpty {
                    Text("The Scripts folder is empty. Drop a `.js` file inside or click **Reinstall Built-in Scripts**.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(scripts) { script in
                        ScriptRow(
                            script: script,
                            isSeed: BuiltInScripts.isSeed(id: script.id),
                            isEnabled: binding(for: script),
                            onRevealFile: { revealFile(for: script) }
                        )
                    }
                }
            } header: {
                Text("Scripts")
            } footer: {
                Text("Toggles appear in the right-click **Run Script** submenu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Scripts Folder") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(ScriptsFolder.url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    HStack {
                        Button {
                            ScriptsFolder.reveal()
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }
                        Button {
                            reload()
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        Button {
                            BuiltInScripts.installIfNeeded()
                            reload()
                        } label: {
                            Label("Reinstall Built-in Scripts", systemImage: "arrow.counterclockwise.circle")
                        }
                    }
                }
            }

            Section("How it works") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each `.js` file is one script. Headers on top describe it:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(sampleHeader)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
                    HStack {
                        Button {
                            showDocs = true
                        } label: {
                            Label("View Documentation", systemImage: "book")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            revealLog()
                        } label: {
                            Label("Reveal Script Log", systemImage: "doc.text")
                        }
                        Spacer()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: reload)
        .sheet(isPresented: $showDocs) {
            ScriptDocsView(
                onClose: { showDocs = false },
                onRevealLog: { revealLog() }
            )
        }
    }

    private func revealLog() {
        let url = ScriptEngine.logURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".data(using: .utf8)?.write(to: url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var sampleHeader: String {
        """
        // @id my-script
        // @name My Script
        // @description What it does
        // @icon sparkles

        input.toUpperCase()
        """
    }

    private func binding(for script: ClipoScript) -> Binding<Bool> {
        Binding<Bool>(
            get: { !disabled.contains(script.id) },
            set: { enabled in
                if enabled { disabled.remove(script.id) }
                else       { disabled.insert(script.id) }
            }
        )
    }

    private func reload() {
        AppState.shared.refreshScripts()
        scripts = AppState.shared.scripts
    }

    private func revealFile(for script: ClipoScript) {
        guard let url = fileURL(for: script) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func fileURL(for script: ClipoScript) -> URL? {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: ScriptsFolder.url, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.pathExtension.lowercased() == "js" {
            let stem = url.deletingPathExtension().lastPathComponent
            if stem == script.id { return url }
            // Fallback: parse @id from file to match
            if let text = try? String(contentsOf: url, encoding: .utf8),
               text.contains("@id \(script.id)") {
                return url
            }
        }
        return nil
    }
}

// MARK: - Row

private struct ScriptRow: View {
    let script: ClipoScript
    let isSeed: Bool
    @Binding var isEnabled: Bool
    let onRevealFile: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((isSeed ? Color.green : Color.accentColor).gradient)
                Image(systemName: script.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(script.name)
                        .font(.system(size: 13, weight: .medium))
                    if isSeed {
                        Text("Built-in")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(script.description.isEmpty ? "No description" : script.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onRevealFile) {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Reveal file in Finder")

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }
}
