import AppKit
import Foundation
import SwiftData

enum ClipKind {
    case text
    case image
    case file
    case url
    case color
}

@Model
final class ClipItem {
    var id: UUID = UUID()
    var firstCopiedAt: Date = Date.now
    var lastCopiedAt: Date = Date.now
    var numberOfCopies: Int = 1
    var sourceAppBundleID: String?
    var title: String = ""
    var pinShortcut: String?

    @Relationship(deleteRule: .cascade, inverse: \ClipContent.item)
    var contents: [ClipContent] = []

    var pinboard: Pinboard?

    private static let transientTypes: [String] = [
        NSPasteboard.PasteboardType.modified.rawValue,
        NSPasteboard.PasteboardType.fromClipo.rawValue,
        NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
        NSPasteboard.PasteboardType.customWebKitPasteboardData.rawValue,
        NSPasteboard.PasteboardType.source.rawValue,
        NSPasteboard.PasteboardType.customChromiumWebData.rawValue,
        NSPasteboard.PasteboardType.chromiumSourceUrl.rawValue,
        NSPasteboard.PasteboardType.chromiumSourceToken.rawValue,
        NSPasteboard.PasteboardType.notesRichText.rawValue
    ]

    init(contents: [ClipContent] = []) {
        self.id = UUID()
        self.firstCopiedAt = .now
        self.lastCopiedAt = .now
        self.contents = contents
    }

    /// Returns true iff `self` contains every non-transient content of `other` — used for dedup.
    func supersedes(_ other: ClipItem) -> Bool {
        other.contents
            .filter { !Self.transientTypes.contains($0.type) }
            .allSatisfy { otherContent in
                contents.contains { $0.type == otherContent.type && $0.value == otherContent.value }
            }
    }

    // MARK: - Content accessors

    private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
        contents.first(where: { types.contains(NSPasteboard.PasteboardType($0.type)) })?.value
    }

    private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
        contents
            .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
            .compactMap { $0.value }
    }

    var fromClipo: Bool { contentData([.fromClipo]) != nil }

    var text: String? {
        guard let data = contentData([.string]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var htmlData: Data? { contentData([.html]) }
    var html: NSAttributedString? {
        guard let data = htmlData else { return nil }
        return NSAttributedString(html: data, documentAttributes: nil)
    }

    var rtfData: Data? { contentData([.rtf]) }
    var rtf: NSAttributedString? {
        guard let data = rtfData else { return nil }
        return NSAttributedString(rtf: data, documentAttributes: nil)
    }

    var imageData: Data? { contentData([.tiff, .png, .jpeg, .heic]) }
    var image: NSImage? {
        guard let data = imageData else { return nil }
        return NSImage(data: data)
    }

    var fileURLs: [URL] {
        allContentData([.fileURL])
            .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
    }

    var primaryKind: ClipKind {
        if !fileURLs.isEmpty { return .file }
        if image != nil { return .image }
        if let t = text, t.looksLikeURL { return .url }
        if let t = text, t.looksLikeColor { return .color }
        return .text
    }

    var previewableText: String {
        if !fileURLs.isEmpty {
            return fileURLs
                .compactMap { $0.absoluteString.removingPercentEncoding }
                .joined(separator: "\n")
        }
        if let text, !text.isEmpty { return text }
        if let rtf, !rtf.string.isEmpty { return rtf.string }
        if let html, !html.string.isEmpty { return html.string }
        return title
    }

    func generateTitle() -> String {
        guard image == nil else { return "" }
        return previewableText
            .shortened(to: 1_000)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var looksLikeURL: Bool {
        guard let url = URL(string: self.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    var looksLikeColor: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }
}
