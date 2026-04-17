import Foundation

/// Reads .js files from `ScriptsFolder.url`, parses their `// @key value`
/// headers, and returns `ClipoScript` instances.
///
/// Supported header keys: `@id`, `@name`, `@description`, `@icon`.
/// All are optional — reasonable defaults are derived from the filename.
enum ScriptLoader {
    static func loadAll() -> [ClipoScript] {
        ScriptsFolder.ensureExists()
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: ScriptsFolder.url,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension.lowercased() == "js" }
            .compactMap(parse(url:))
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func parse(url: URL) -> ClipoScript? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let (meta, body) = splitHeaderAndBody(text)
        let stem = url.deletingPathExtension().lastPathComponent
        return ClipoScript(
            id: meta["id"] ?? stem,
            name: meta["name"] ?? stem,
            icon: meta["icon"] ?? "play.fill",
            description: meta["description"] ?? "",
            source: body
        )
    }

    /// Walks leading comment lines, collecting `@key value` pairs. Stops at
    /// the first non-comment, non-blank line — the rest is the body.
    private static func splitHeaderAndBody(_ text: String) -> ([String: String], String) {
        var meta: [String: String] = [:]
        var bodyStart = text.startIndex
        var inHeader = true

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var cursor = text.startIndex

        for line in lines {
            let lineLength = line.count + 1 // include \n
            let lineEnd = text.index(cursor, offsetBy: min(lineLength, text.distance(from: cursor, to: text.endIndex)))
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inHeader {
                if trimmed.isEmpty {
                    cursor = lineEnd
                    continue
                }
                if trimmed.hasPrefix("//") {
                    let rest = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                    if rest.hasPrefix("@"), let space = rest.firstIndex(of: " ") {
                        let key = String(rest[rest.index(after: rest.startIndex)..<space])
                            .trimmingCharacters(in: .whitespaces)
                        let value = String(rest[rest.index(after: space)...])
                            .trimmingCharacters(in: .whitespaces)
                        if !key.isEmpty { meta[key] = value }
                    }
                    cursor = lineEnd
                    continue
                }
                // First non-comment, non-blank line — body starts here.
                inHeader = false
                bodyStart = cursor
                break
            }
            cursor = lineEnd
        }
        if inHeader { bodyStart = text.endIndex }
        let body = String(text[bodyStart...])
        return (meta, body)
    }
}
