import AppKit

/// Process-wide cache of source-app icons, keyed by bundle identifier.
/// Cards in the carousel each display the source-app icon, and
/// `NSWorkspace.icon(forFile:)` is surprisingly non-trivial —  it hits the
/// LaunchServices database and allocates a new NSImage every call. Caching
/// is safe because an app's icon rarely changes while Clipo is running.
enum AppIconCache {
    private static let cache = NSCache<NSString, NSImage>()
    private static let missingIcon: NSImage = {
        // Pre-size a single generic fallback so we don't allocate one per miss.
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 16, height: 16))
    }()

    /// Returns the source app's icon at `size`. For a missing bundle we
    /// return a generic `app.dashed` glyph. Nil means no bundle was given.
    static func icon(forBundleID bundleID: String?, size: CGFloat = 20) -> NSImage? {
        guard let bundleID else { return nil }
        let key = "\(bundleID)@\(Int(size))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            cache.setObject(missingIcon, forKey: key)
            return missingIcon
        }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: size, height: size)
        cache.setObject(img, forKey: key)
        return img
    }
}
