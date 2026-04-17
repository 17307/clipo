import AppKit

/// Process-wide cache of source-app icons and file-type icons.
///
/// - App icons are keyed by `bundleID@size` and hit LaunchServices once.
/// - File icons are keyed by extension@size — every `.pdf` or `.txt`
///   shares one icon, so a 100-file preview list makes one lookup instead
///   of 100.
///
/// The cache is byte-aware (`totalCostLimit = 32 MB`) so repeatedly
/// decoded high-resolution icons can't pile up without bound; NSCache
/// evicts under memory pressure as well.
enum AppIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 32 * 1024 * 1024   // ~32 MB of NSImage data
        c.countLimit = 512
        return c
    }()

    private static let missingAppIcon: NSImage = {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }()

    /// Source-app icon by bundle id. Nil means no bundle was given.
    static func icon(forBundleID bundleID: String?, size: CGFloat = 20) -> NSImage? {
        guard let bundleID else { return nil }
        let key = "app:\(bundleID)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            store(missingAppIcon, forKey: key, size: size)
            return missingAppIcon
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        store(img, forKey: key, size: size)
        return img
    }

    /// Icon for a file URL, keyed by extension so same-type files share.
    /// Falls back to path-specific lookup if extension is empty.
    static func icon(forFile url: URL, size: CGFloat = 24) -> NSImage {
        let ext = url.pathExtension.lowercased()
        let key = (ext.isEmpty ? "file:\(url.path)" : "ext:\(ext)") + "@\(Int(size))"
        let nsKey = key as NSString
        if let cached = cache.object(forKey: nsKey) { return cached }

        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        store(img, forKey: nsKey, size: size)
        return img
    }

    // MARK: - Cost estimation

    /// Approximate the memory footprint of an NSImage so NSCache's byte
    /// cap is roughly meaningful. Typical app icons are 128×128 @2x = 256KB.
    private static func estimatedBytes(for image: NSImage, size: CGFloat) -> Int {
        let pixels = Int(size * size)
        return max(pixels * 4, 1024)  // RGBA8 baseline, minimum 1KB
    }

    private static func store(_ image: NSImage, forKey key: NSString, size: CGFloat) {
        cache.setObject(image, forKey: key, cost: estimatedBytes(for: image, size: size))
    }
}
