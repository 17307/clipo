import AppKit
import Defaults
import SwiftUI

struct StoragePane: View {
    @Default(.maxHistorySize) private var maxHistorySize
    @Default(.enabledPasteboardTypes) private var enabledTypes
    @Default(.sortBy) private var sortBy

    @State private var storageSize: String = "—"
    @State private var showClearConfirm = false

    private static let textTypes: Set<NSPasteboard.PasteboardType> = [.string, .html, .rtf]
    private static let imageTypes: Set<NSPasteboard.PasteboardType> = [.png, .tiff, .jpeg, .heic]
    private static let fileTypes: Set<NSPasteboard.PasteboardType> = [.fileURL]

    var body: some View {
        Form {
            Section("History size") {
                HStack {
                    TextField("", value: $maxHistorySize, formatter: Self.intFormatter)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                    Stepper("", value: $maxHistorySize, in: 1...5000, step: 10)
                        .labelsHidden()
                    Text("items").foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Oldest items are removed once this limit is exceeded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Save") {
                Toggle("Text", isOn: typeGroupBinding(Self.textTypes))
                Toggle("Images", isOn: typeGroupBinding(Self.imageTypes))
                Toggle("Files", isOn: typeGroupBinding(Self.fileTypes))
            }

            Section("Sort by") {
                Picker("Sort by", selection: $sortBy) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Storage") {
                HStack {
                    Text("Location:").foregroundStyle(.secondary)
                    Text(storageURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal") { revealInFinder() }
                }
                HStack {
                    Text("Size:").foregroundStyle(.secondary)
                    Text(storageSize)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Text("Clear History…")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear(perform: refreshStorageSize)
        .alert("Clear all history?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                AppState.shared.clearAll()
                refreshStorageSize()
            }
        } message: {
            Text("Unpinned items will be removed permanently. Items in Pinboards are kept.")
        }
    }

    // MARK: - Helpers

    private static let intFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 5000
        return f
    }()

    private var storageURL: URL {
        URL.applicationSupportDirectory.appending(path: "Clipo/Storage.sqlite")
    }

    private func refreshStorageSize() {
        if let size = try? storageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 {
            storageSize = SharedFormatters.byteCount.string(fromByteCount: Int64(size))
        } else {
            storageSize = "—"
        }
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([storageURL])
    }

    private func typeGroupBinding(_ group: Set<NSPasteboard.PasteboardType>) -> Binding<Bool> {
        Binding<Bool>(
            get: { !group.isEmpty && group.isSubset(of: enabledTypes) },
            set: { newValue in
                if newValue { enabledTypes.formUnion(group) }
                else { enabledTypes.subtract(group) }
            }
        )
    }
}
