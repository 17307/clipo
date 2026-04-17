import Defaults
import KeyboardShortcuts
import SwiftUI

struct GeneralPane: View {
    @Default(.searchMode) private var searchMode
    @Default(.pasteByDefault) private var pasteByDefault
    @Default(.removeFormattingByDefault) private var removeFormatting
    @Default(.checkInterval) private var checkInterval

    var body: some View {
        Form {
            Section("Startup") {
                LaunchAtLoginToggle()
            }

            Section("Global shortcut") {
                LabeledContent("Show / Hide Clipo") {
                    KeyboardShortcuts.Recorder(for: .togglePanel)
                }
            }

            Section("Panel shortcuts") {
                LabeledContent("Copy Again") {
                    KeyboardShortcuts.Recorder(for: .copyAgain)
                }
                LabeledContent("Paste as Plain Text") {
                    KeyboardShortcuts.Recorder(for: .pastePlain)
                }
                LabeledContent("Paste with Formatting") {
                    KeyboardShortcuts.Recorder(for: .pasteFormatted)
                }
                Text("Active only while the Clipo panel is open — these shortcuts don't intercept keystrokes in other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Paste") {
                Toggle("Paste automatically after selecting an item", isOn: $pasteByDefault)
                Toggle("Paste without formatting by default", isOn: $removeFormatting)
            }

            Section("Search mode") {
                Picker("Search mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(searchModeHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Clipboard monitor") {
                HStack {
                    Slider(value: $checkInterval, in: 0.1...2.0, step: 0.1)
                    Text(String(format: "%.1f s", checkInterval))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }
                Text("How often Clipo polls the system clipboard. Lower = faster capture, higher CPU.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var searchModeHelp: String {
        switch searchMode {
        case .exact:    return "Match only exact substrings."
        case .contains: return "Match when the query appears anywhere in the item."
        case .fuzzy:    return "Allow loose matching (skipped characters)."
        }
    }
}
