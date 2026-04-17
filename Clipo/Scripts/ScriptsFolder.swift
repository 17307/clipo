import AppKit
import Foundation

/// Location for user-provided scripts. `ensureExists()` lazily creates the
/// folder; `reveal()` opens it in Finder.
enum ScriptsFolder {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "Clipo/Scripts", directoryHint: .isDirectory)
    }

    static func ensureExists() {
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true
        )
    }

    static func reveal() {
        ensureExists()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
