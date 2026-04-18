import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds an `NSItemProvider` suitable for SwiftUI's `.onDrag` modifier.
///
/// Background on the chosen pattern
/// --------------------------------
/// - macOS drag targets (Finder, Keynote, Figma, Mail attachment wells,
///   every browser's native file-upload, etc.) almost universally want
///   the drag content to be a **file URL**.
/// - SwiftUI `.onDrag` doesn't bridge to `NSFilePromiseProvider`
///   (see https://wadetregaskis.com/swiftui-drag-drop-does-not-support-file-promises/).
///   The documented workaround is
///   `NSItemProvider().registerDataRepresentation(for: UTType.fileURL)`
///   with a lazy loader that materialises a temp file only when the
///   drop target asks for it.
/// - The loader writes to a per-session temp directory and hands back
///   the URL's data representation. If the user never drops (just
///   cancels), no file is ever written.
///
/// We already tried a custom AppKit `beginDraggingSession` route — it
/// kept triggering `kDragIPCWithinWindow` reentrancy errors in Finder
/// because the app was routed through both
/// `com.apple.ensemble.dragserver` AND
/// `com.apple.windowmanager.dragserver`. SwiftUI's `.onDrag`
/// specifically goes through just one of those, which is why this
/// pattern works where direct AppKit calls did not.
enum DragProvider {
    /// Returns an item provider that, on demand, serialises the clip
    /// item to a temp file whose URL is handed to the drop target.
    ///
    /// Snapshots everything the lazy loader might need at call time
    /// (while we're still on the main actor, since ClipItem is a
    /// SwiftData @Model) into a plain `MaterializedPayload`. The loader
    /// closure then only touches that value type, safely runnable from
    /// whatever background thread the system dispatches it on.
    @MainActor
    static func makeProvider(for item: ClipItem) -> NSItemProvider {
        // Existing file items: just offer the original URL. No copy.
        if let fileURL = item.fileURLs.first {
            return NSItemProvider(object: fileURL as NSURL)
        }
        guard let payload = payloadSnapshot(for: item) else {
            return NSItemProvider()
        }
        let provider = NSItemProvider()
        provider.suggestedName = payload.filename
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            do {
                let url = try writeTempFile(payload: payload)
                completion(url.dataRepresentation, nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        return provider
    }

    /// Plain value type — safe to capture into the loader closure that
    /// runs on a background thread.
    private struct MaterializedPayload: Sendable {
        let data: Data
        let filename: String
    }

    private static func writeTempFile(payload: MaterializedPayload) throws -> URL {
        let root = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL.temporaryDirectory,
            create: true
        )
        let url = root.appending(path: payload.filename, directoryHint: .notDirectory)
        try payload.data.write(to: url, options: .atomic)
        return url
    }

    @MainActor
    private static func payloadSnapshot(for item: ClipItem) -> MaterializedPayload? {
        let stem = nameStem(for: item)
        if let imageData = item.imageData, !imageData.isEmpty {
            let ext = imageExtension(for: imageData)
            return MaterializedPayload(
                data: imageData,
                filename: "\(stem).\(ext)"
            )
        }
        let text = item.previewableText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let data = text.data(using: .utf8) else {
            return nil
        }
        return MaterializedPayload(
            data: data,
            filename: "\(stem).txt"
        )
    }

    @MainActor
    private static func nameStem(for item: ClipItem) -> String {
        let firstLine = item.previewableText
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? ""
        let trimmed = firstLine
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: "_")
        let bounded = String(trimmed.prefix(40)).trimmingCharacters(in: .whitespaces)
        if !bounded.isEmpty { return bounded }
        return "clipo-\(item.id.uuidString.prefix(8))"
    }

    /// Sniff the first few bytes so the temp file carries a correct
    /// extension — lets Finder show the right icon and apps that key
    /// off extension rather than magic bytes work correctly.
    private static func imageExtension(for data: Data) -> String {
        guard data.count >= 12 else { return "png" }
        return data.withUnsafeBytes { buf -> String in
            let b = buf.bindMemory(to: UInt8.self)
            guard b.count >= 12 else { return "png" }
            if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "png" }
            if b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "jpg" }
            if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return "gif" }
            if b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
               b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 {
                return "webp"
            }
            if (b[0] == 0x49 && b[1] == 0x49) || (b[0] == 0x4D && b[1] == 0x4D) {
                return "tiff"
            }
            return "png"
        }
    }
}

private enum DragProviderError: Error {
    case noExportableContent
}
