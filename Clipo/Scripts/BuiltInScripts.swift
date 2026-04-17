import Foundation

/// Seed scripts that ship inside the app. On first launch each seed is
/// written to the user's Scripts folder (`~/Library/Application Support/Clipo/Scripts/`)
/// if a file with the same name is not already there. Users can then edit,
/// rename, or delete them; Clipo always reads from disk afterwards.
enum BuiltInScripts {
    struct Seed {
        let filename: String
        let content: String
    }

    static let seeds: [Seed] = [
        Seed(filename: "base64-encode.js", content: """
            // @id base64-encode
            // @name Base64 Encode
            // @description Encode text as Base64.
            // @icon lock.shield

            // `input` is the selected item's text. Return a string and Clipo
            // copies it to the clipboard + shows the result preview.
            __base64Encode(input)
            """),

        Seed(filename: "base64-decode.js", content: """
            // @id base64-decode
            // @name Base64 Decode
            // @description Decode Base64-encoded text.
            // @icon lock.open

            __base64Decode(input)
            """),

        Seed(filename: "url-encode.js", content: """
            // @id url-encode
            // @name URL Encode
            // @description Percent-encode for URL query strings.
            // @icon link

            __urlEncode(input)
            """),

        Seed(filename: "url-decode.js", content: """
            // @id url-decode
            // @name URL Decode
            // @description Decode percent-encoded URL text.
            // @icon link.badge.plus

            __urlDecode(input)
            """),

        Seed(filename: "trim-whitespace.js", content: """
            // @id trim-whitespace
            // @name Trim Whitespace
            // @description Remove leading/trailing whitespace.
            // @icon scissors

            // Pure-JS example: no helpers used.
            input.trim()
            """),

        Seed(filename: "format-json.js", content: """
            // @id format-json
            // @name Format JSON
            // @description Pretty-print JSON with 2-space indent.
            // @icon curlybraces.square

            // Shows try/catch, JSON stdlib, and a fallback value.
            try {
              const obj = JSON.parse(input);
              JSON.stringify(obj, null, 2);
            } catch (e) {
              console.log("format-json: " + e.message);
              input; // fall back to original text on parse error
            }
            """),

        Seed(filename: "count-stats.js", content: """
            // @id count-stats
            // @name Count Stats
            // @description Report chars / words / lines for the input.
            // @icon number

            // Template literals + methods on String. Result is multi-line text.
            const lines = input.split("\\n").length;
            const words = input.trim().split(/\\s+/).filter(Boolean).length;
            const chars = input.length;
            `chars: ${chars}\\nwords: ${words}\\nlines: ${lines}`
            """),
    ]

    /// Ensures the Scripts folder exists and copies any missing seeds.
    /// Never overwrites files the user may have edited.
    static func installIfNeeded() {
        ScriptsFolder.ensureExists()
        let fm = FileManager.default
        for seed in seeds {
            let url = ScriptsFolder.url.appending(path: seed.filename)
            guard !fm.fileExists(atPath: url.path) else { continue }
            try? seed.content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func isSeed(id: String) -> Bool {
        seeds.contains { seed in
            extractSeedID(from: seed.content) == id
        }
    }

    private static func extractSeedID(from content: String) -> String? {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") else { continue }
            let body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("@id ") {
                return body.dropFirst(4).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
