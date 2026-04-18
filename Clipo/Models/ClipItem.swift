import AppKit
import Foundation
import SwiftData

enum ClipKind: Int {
    case text = 0
    case image = 1
    case file = 2
    case url = 3
    case color = 4
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

    // MARK: - Decoded-value caches
    //
    // Raw content `Data` is persisted by SwiftData. Decoding the same bytes
    // into an `NSImage` or parsing `previewableText` runs every time a card
    // re-renders, which gets expensive when scrolling a carousel of photos
    // or long text blocks. These process-wide NSCaches survive for the
    // lifetime of the ClipItem (keyed by its UUID) and let NSCache evict
    // automatically under memory pressure.
    private static let imageCache: NSCache<NSUUID, NSImage> = {
        let c = NSCache<NSUUID, NSImage>()
        c.countLimit = 200
        return c
    }()
    private static let textCache: NSCache<NSUUID, NSString> = {
        let c = NSCache<NSUUID, NSString>()
        c.countLimit = 500
        return c
    }()
    /// Kind is otherwise O(N × image-decode) when filtering by Images/Files —
    /// `image != nil` used to call `NSImage(data:)` just to answer a boolean.
    /// Cache the answer so filtering and card rendering are O(1).
    private static let kindCache: NSCache<NSUUID, NSNumber> = {
        let c = NSCache<NSUUID, NSNumber>()
        c.countLimit = 4000
        return c
    }()

    var image: NSImage? {
        let key = id as NSUUID
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let data = imageData, let img = NSImage(data: data) else { return nil }
        Self.imageCache.setObject(img, forKey: key)
        return img
    }

    var fileURLs: [URL] {
        allContentData([.fileURL])
            .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
    }

    var primaryKind: ClipKind {
        let key = id as NSUUID
        if let cached = Self.kindCache.object(forKey: key),
           let k = ClipKind(rawValue: cached.intValue) {
            return k
        }
        let result: ClipKind
        if !fileURLs.isEmpty {
            result = .file
        } else if imageData != nil {
            // Check presence only — do NOT decode the bytes into an NSImage
            // just to answer "is this an image?". Decode happens lazily in
            // the `image` accessor when a card actually renders.
            result = .image
        } else if let t = text, t.looksLikeURL {
            result = .url
        } else if let t = text, t.looksLikeColor {
            result = .color
        } else {
            result = .text
        }
        Self.kindCache.setObject(NSNumber(value: result.rawValue), forKey: key)
        return result
    }

    var previewableText: String {
        let key = id as NSUUID
        if let cached = Self.textCache.object(forKey: key) { return cached as String }
        let result: String = {
            if !fileURLs.isEmpty {
                return fileURLs
                    .compactMap { $0.absoluteString.removingPercentEncoding }
                    .joined(separator: "\n")
            }
            if let text, !text.isEmpty { return text }
            if let rtf, !rtf.string.isEmpty { return rtf.string }
            if let html, !html.string.isEmpty { return html.string }
            return title
        }()
        Self.textCache.setObject(result as NSString, forKey: key)
        return result
    }

    func generateTitle() -> String {
        // Avoid decoding the bitmap during ingest — a presence check on the
        // raw bytes is enough to know "this item is an image, don't compute
        // a textual title for it." The NSImage decode happens lazily when a
        // card actually renders.
        guard imageData == nil else { return "" }
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
