import Foundation

/// Formatters are surprisingly expensive to construct — a few hundred µs each
/// on Apple Silicon — and a carousel of 500 cards renders them repeatedly.
/// Centralize instances here so every view reuses one.
enum SharedFormatters {
    /// "2m ago" / "yesterday" etc. Thread-safe for reads on main actor.
    static let relativeTime: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.dateTimeStyle = .named
        return f
    }()

    /// Same formatter but with `.full` unit style for the preview header
    /// where the extra horizontal space reads "2 minutes ago" nicely.
    static let relativeTimeFull: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f
    }()

    static let byteCount = ByteCountFormatter()
}
