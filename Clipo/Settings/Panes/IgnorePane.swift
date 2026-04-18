import AppKit
import Defaults
import SwiftUI

struct IgnorePane: View {
    var body: some View {
        TabView {
            IgnoreAppsTab()
                .tabItem { Label("Apps", systemImage: "app.dashed") }
            IgnoreTypesTab()
                .tabItem { Label("Types", systemImage: "doc.text") }
            IgnoreRegexTab()
                .tabItem { Label("Regex", systemImage: "textformat") }
        }
        .padding()
    }
}

// MARK: - Apps

private struct IgnoreAppsTab: View {
    @Default(.ignoredApps) private var ignoredApps
    @Default(.ignoreAllAppsExceptListed) private var invert

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Only capture from apps in this list", isOn: $invert)
            Text(invert
                 ? "Whitelist mode: ignore everything else."
                 : "Blacklist mode: ignore the apps listed below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            if ignoredApps.isEmpty {
                Text("No apps added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(ignoredApps, id: \.self) { bundleID in
                            AppRow(bundleID: bundleID) {
                                ignoredApps.removeAll { $0 == bundleID }
                            }
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Button("Add App…") { addApp() }
                Spacer()
            }
        }
        .padding(12)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
           !ignoredApps.contains(id) {
            ignoredApps.append(id)
        }
    }
}

private struct AppRow: View {
    let bundleID: String
    let onRemove: () -> Void

    @State private var icon: NSImage?
    @State private var appName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                } else {
                    // Neutral placeholder while LaunchServices is queried off
                    // the main thread. Keeps list open latency flat regardless
                    // of how many rows are present.
                    Image(systemName: "app.dashed")
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(appName.isEmpty ? bundleID : appName)
                Text(bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
        .task(id: bundleID) {
            await loadIcon(for: bundleID)
        }
    }

    private func loadIcon(for id: String) async {
        let result: (name: String, icon: NSImage?) = await Task.detached(priority: .utility) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return (id, nil)
            }
            let name = FileManager.default.displayName(atPath: url.path)
            // AppIconCache normalises size + caches by bundle id so repeat
            // opens of this pane are free.
            let img = AppIconCache.icon(forBundleID: id, size: 20)
            return (name, img)
        }.value
        guard !Task.isCancelled else { return }
        appName = result.name
        icon = result.icon
    }
}

// MARK: - Types

private struct IgnoreTypesTab: View {
    @Default(.ignoredPasteboardTypes) private var types
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pasteboard types to ignore (e.g. `org.nspasteboard.ConcealedType`).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if types.isEmpty {
                Text("No types ignored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(types), id: \.self) { type in
                            HStack {
                                Text(type)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                Spacer()
                                Button(role: .destructive) {
                                    types.remove(type)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            HStack {
                TextField("com.example.pasteboardType", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addType)
                Button("Add") { addType() }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func addType() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        types.insert(t)
        draft = ""
    }
}

// MARK: - Regex

private struct IgnoreRegexTab: View {
    @Default(.ignoreRegexp) private var patterns
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Regular expressions. Copies whose text matches any pattern are not recorded.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if patterns.isEmpty {
                Text("No patterns added.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(patterns.enumerated()), id: \.offset) { idx, _ in
                            RegexRow(
                                value: Binding(
                                    get: { patterns[idx] },
                                    set: { patterns[idx] = $0 }
                                ),
                                onRemove: { patterns.remove(at: idx) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            HStack {
                TextField("^\\d{16}$", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(addPattern)
                Button("Add") { addPattern() }
                    .disabled(draft.isEmpty || !isValid(draft))
            }
        }
        .padding(12)
    }

    private func addPattern() {
        guard isValid(draft) else { return }
        patterns.append(draft)
        draft = ""
    }

    private func isValid(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}

private struct RegexRow: View {
    @Binding var value: String
    let onRemove: () -> Void

    private var isValid: Bool { (try? NSRegularExpression(pattern: value)) != nil }

    var body: some View {
        HStack {
            TextField("", text: $value)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isValid ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
                )
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
        }
    }
}
