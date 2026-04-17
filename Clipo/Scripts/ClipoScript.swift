import Foundation

struct ClipoScript: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String        // SF Symbol name
    let description: String
    /// JavaScript source. Two globals are injected before execution:
    ///   • `input`  — the item's text (String)
    ///   • `__base64Encode(s)` / `__base64Decode(s)` — Swift-backed helpers
    /// The script's final expression result is taken as the output string.
    let source: String
}
