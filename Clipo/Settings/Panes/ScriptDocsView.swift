import AppKit
import SwiftUI

struct ScriptDocsView: View {
    let onClose: () -> Void
    let onRevealLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overview
                    metadata
                    inputOutput
                    helpers
                    stdlib
                    limits
                    tips
                }
                .padding(22)
            }
        }
        .frame(width: 640, height: 640)
    }

    private var header: some View {
        HStack {
            Label("Scripting Guide", systemImage: "curlybraces")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("Reveal Log") { onRevealLog() }
                .buttonStyle(.bordered)
            Button("Done", action: onClose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var overview: some View {
        section(title: "Overview") {
            paragraph("""
            Scripts are JavaScript files in \
            `~/Library/Application Support/Clipo/Scripts/`. When you right-click \
            a clipboard item and pick **Run Script ▸ X**, Clipo runs the file \
            in a fresh JavaScriptCore context, copies the result to the \
            clipboard, and shows it in the preview window.
            """)
        }
    }

    private var metadata: some View {
        section(title: "File Header") {
            paragraph("""
            Comments at the top of the file declare metadata. All keys are optional; \
            reasonable defaults are derived from the filename.
            """)
            code("""
            // @id        my-script            // unique id (default: filename)
            // @name      My Script            // shown in the menu
            // @description What it does        // shown in Settings
            // @icon      sparkles             // SF Symbol name
            """)
        }
    }

    private var inputOutput: some View {
        section(title: "Input and Output") {
            bullet("**`input`**  —  the selected item's text (string).")
            bullet("""
            **return value**  —  the script's *last expression* is the result. \
            Clipo casts it with `String(result)`. An `undefined` / `null` result is treated as an error.
            """)
            code("""
            // simplest: one expression, implicit return
            input.toUpperCase()

            // or wrap logic and evaluate the final value
            const parts = input.split(",");
            parts.map(s => s.trim()).join("\\n")
            """)
        }
    }

    private var helpers: some View {
        section(title: "Built-in helpers") {
            helperRow("__base64Encode(s)",  "UTF-8 text  →  Base64")
            helperRow("__base64Decode(s)",  "Base64  →  UTF-8 text")
            helperRow("__urlEncode(s)",     "Percent-encode for URL query strings")
            helperRow("__urlDecode(s)",     "Decode percent-encoded text")
            helperRow("console.log(msg)",   "Append a message to the script log file")
        }
    }

    private var stdlib: some View {
        section(title: "JS Standard Library") {
            paragraph("""
            JavaScriptCore ships a modern JS runtime — ES2017+ language \
            features and the standard built-ins are all available:
            """)
            bullet("Strings: `toUpperCase`, `split`, `replace`, template literals, regex (`match`, `replaceAll`, …).")
            bullet("`JSON.parse` / `JSON.stringify(obj, null, 2)` for structured data.")
            bullet("`Math`, `Date`, `Array`, `Object`, `Map`, `Set`, `Promise`.")
            bullet("`try` / `catch` for error handling; arrow functions; `const` / `let`; destructuring.")
        }
    }

    private var limits: some View {
        section(title: "What's not available") {
            bullet("No DOM / `document` / `window`.")
            bullet("No network I/O (`fetch`, `XMLHttpRequest`).")
            bullet("No timers (`setTimeout` / `setInterval`) — scripts run synchronously.")
            bullet("No filesystem or process APIs.")
            paragraph("These are intentional: scripts are pure transforms on the clipboard text.")
        }
    }

    private var tips: some View {
        section(title: "Tips") {
            bullet("Use `console.log(...)` to debug — click **Reveal Log** above to open the log file.")
            bullet("Return the original `input` on error so nothing is lost.")
            bullet("Scripts are reloaded from disk on every menu open — edit in place, no restart needed.")
            bullet("Delete a seed script you don't want; use **Reinstall Built-in Scripts** in Settings to bring them back.")
        }
    }

    // MARK: - Helpers

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(.init(text))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.1)))
            .textSelection(.enabled)
    }

    private func helperRow(_ api: String, _ description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(api)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.12)))
                .frame(minWidth: 170, alignment: .leading)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
