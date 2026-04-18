import Foundation

/// Installs / uninstalls the bundled `clipocli` binary on the user's shell
/// `$PATH` by editing the file `~/.zshrc`.
///
/// Safety model: we NEVER modify arbitrary lines. Everything we write is
/// bracketed by unique marker comments — `# >>> clipo-cli >>>` and
/// `# <<< clipo-cli <<<` — and the uninstaller only removes the block
/// between those markers. Anything the user adds to their own .zshrc
/// (including manual PATH customization for other tools) is untouched.
///
/// The exported directory is `Bundle.main.resourcePath` (i.e.
/// `Clipo.app/Contents/Resources/`), which is where build-release.sh
/// stages the `clipocli` binary.
enum CLIPathInstaller {
    static let markerBegin = "# >>> clipo-cli >>>"
    static let markerEnd   = "# <<< clipo-cli <<<"

    // MARK: - Paths

    /// Directory containing the `clipocli` binary inside the running app bundle.
    static var cliDirectory: String {
        Bundle.main.resourcePath ?? ""
    }

    /// Full path to the bundled CLI.
    static var cliBinaryPath: String {
        (cliDirectory as NSString).appendingPathComponent("clipocli")
    }

    /// Target shell RC file. We only edit ~/.zshrc (macOS default since
    /// Catalina). Fish / bash users can copy the exported block manually.
    static var zshrcURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".zshrc")
    }

    // MARK: - Introspection

    /// True when our managed block exists in the current ~/.zshrc.
    static func isInstalled() -> Bool {
        guard let contents = try? String(contentsOf: zshrcURL, encoding: .utf8) else {
            return false
        }
        return contents.contains(markerBegin) && contents.contains(markerEnd)
    }

    /// True when an install is present but points at a directory different
    /// from the currently-running app's Resources path (e.g. the app was
    /// moved). Caller can offer a "Reinstall" button.
    static func isOutdated() -> Bool {
        guard let contents = try? String(contentsOf: zshrcURL, encoding: .utf8),
              contents.contains(markerBegin) else { return false }
        let wanted = "\"$PATH:\(cliDirectory)\""
        return !contents.contains(wanted)
    }

    enum InstallError: Error, LocalizedError {
        case cannotReadRC(underlying: Error)
        case cannotWriteRC(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .cannotReadRC(let e): return "Could not read ~/.zshrc: \(e.localizedDescription)"
            case .cannotWriteRC(let e): return "Could not write ~/.zshrc: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Install / uninstall

    /// Adds (or refreshes) the clipo-cli managed block in ~/.zshrc.
    /// If a block already exists, it's replaced in-place so relocating the
    /// app bundle only requires clicking "Install" again.
    static func install() throws {
        let block = renderBlock()
        let existing = (try? String(contentsOf: zshrcURL, encoding: .utf8)) ?? ""

        let updated: String
        if existing.contains(markerBegin) {
            // Replace existing block so a moved app bundle is fixed automatically.
            updated = replaceManagedBlock(in: existing, with: block)
        } else {
            // Append; ensure the file ends with a newline before we do.
            var prefix = existing
            if !prefix.isEmpty && !prefix.hasSuffix("\n") { prefix += "\n" }
            if !prefix.isEmpty { prefix += "\n" }  // blank line for visual separation
            updated = prefix + block + "\n"
        }

        do {
            try updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.cannotWriteRC(underlying: error)
        }
    }

    /// Removes the clipo-cli managed block from ~/.zshrc if present.
    /// All other lines are left untouched. No-op if no block is found.
    static func uninstall() throws {
        guard let existing = try? String(contentsOf: zshrcURL, encoding: .utf8),
              existing.contains(markerBegin) else {
            return  // nothing to do
        }
        let updated = removeManagedBlock(from: existing)
        do {
            try updated.write(to: zshrcURL, atomically: true, encoding: .utf8)
        } catch {
            throw InstallError.cannotWriteRC(underlying: error)
        }
    }

    // MARK: - Block builders

    private static func renderBlock() -> String {
        """
        \(markerBegin)
        # Managed by Clipo — do not edit these three lines manually.
        # Removing them via Settings → Advanced will leave the rest of
        # this file unchanged.
        export PATH="$PATH:\(cliDirectory)"
        \(markerEnd)
        """
    }

    /// Remove the block including the marker lines themselves. Non-greedy
    /// match between the two markers; if marker pairs ever somehow end up
    /// nested (they shouldn't), only the first outer block is removed.
    private static func removeManagedBlock(from text: String) -> String {
        guard let begin = text.range(of: markerBegin),
              let end = text.range(of: markerEnd, range: begin.upperBound..<text.endIndex) else {
            return text
        }
        // Absorb an immediately-following newline so we don't leave blank gaps.
        var removeEnd = end.upperBound
        if removeEnd < text.endIndex, text[removeEnd] == "\n" {
            removeEnd = text.index(after: removeEnd)
        }
        // Also absorb a blank line immediately before the marker if present,
        // so repeated install/uninstall cycles don't accumulate empty lines.
        var removeStart = begin.lowerBound
        if removeStart > text.startIndex {
            let prevIdx = text.index(before: removeStart)
            if text[prevIdx] == "\n", prevIdx > text.startIndex {
                let prev2 = text.index(before: prevIdx)
                if text[prev2] == "\n" {
                    removeStart = prevIdx
                }
            }
        }
        var result = text
        result.removeSubrange(removeStart..<removeEnd)
        return result
    }

    private static func replaceManagedBlock(in text: String, with block: String) -> String {
        guard let begin = text.range(of: markerBegin),
              let end = text.range(of: markerEnd, range: begin.upperBound..<text.endIndex) else {
            return text
        }
        var result = text
        result.replaceSubrange(begin.lowerBound..<end.upperBound, with: block)
        return result
    }
}
