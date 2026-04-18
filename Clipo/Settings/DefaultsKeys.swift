import AppKit
import Defaults
import Foundation

enum SearchMode: String, Defaults.Serializable, CaseIterable, Identifiable {
    case exact, contains, fuzzy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .exact:    return "Exact"
        case .contains: return "Contains"
        case .fuzzy:    return "Fuzzy"
        }
    }
}

enum SortMode: String, Defaults.Serializable, CaseIterable, Identifiable {
    case lastCopiedAt, firstCopiedAt, numberOfCopies
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastCopiedAt:   return "Last Copied"
        case .firstCopiedAt:  return "First Copied"
        case .numberOfCopies: return "Most Used"
        }
    }
}

enum MenuBarIcon: String, Defaults.Serializable, CaseIterable, Identifiable {
    case clipboard = "doc.on.clipboard"
    case tray = "tray.full"
    case simple = "clipboard"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .tray:      return "Tray"
        case .simple:    return "Simple"
        }
    }
}

extension Defaults.Keys {
    // Clipboard engine
    static let checkInterval = Key<TimeInterval>("checkInterval", default: 0.5)
    static let maxHistorySize = Key<Int>("maxHistorySize", default: 500)
    /// Per-item byte ceiling. Anything whose total content bytes exceed this
    /// is silently dropped instead of being ingested. Protects SwiftData +
    /// NSCache from a 50 MB-PDF paste freezing the app. Default 20 MB.
    static let maxItemBytes = Key<Int>("maxItemBytes", default: 20 * 1024 * 1024)
    static let enabledPasteboardTypes = Key<Set<NSPasteboard.PasteboardType>>(
        "enabledPasteboardTypes",
        default: [.fileURL, .html, .png, .rtf, .string, .tiff]
    )
    static let ignoredPasteboardTypes = Key<Set<String>>("ignoredPasteboardTypes", default: [])
    static let ignoredApps = Key<[String]>("ignoredApps", default: [])
    static let ignoreAllAppsExceptListed = Key<Bool>("ignoreAllAppsExceptListed", default: false)
    static let ignoreRegexp = Key<[String]>("ignoreRegexp", default: [])
    static let ignoreEvents = Key<Bool>("ignoreEvents", default: false)

    // UI - layout
    static let panelHeight = Key<Double>("panelHeight", default: 330)
    static let panelBottomInset = Key<Double>("panelBottomInset", default: 0)

    // UI - appearance (new)
    static let menuBarIcon = Key<MenuBarIcon>("menuBarIcon", default: .clipboard)
    static let accentColorHex = Key<String>("accentColorHex", default: "#FF6A3D")
    static let showSourceIcon = Key<Bool>("showSourceIcon", default: true)
    static let showFooterHints = Key<Bool>("showFooterHints", default: true)

    // Behavior (new)
    static let searchMode = Key<SearchMode>("searchMode", default: .contains)
    static let sortBy = Key<SortMode>("sortBy", default: .lastCopiedAt)

    // Paste behavior
    static let pasteByDefault = Key<Bool>("pasteByDefault", default: true)
    static let removeFormattingByDefault = Key<Bool>("removeFormattingByDefault", default: true)
    static let clearSystemClipboard = Key<Bool>("clearSystemClipboard", default: false)
    static let clearOnQuit = Key<Bool>("clearOnQuit", default: false)

    // Scripts — IDs that are disabled (unchecked in Settings).
    static let disabledScriptIDs = Key<Set<String>>("disabledScriptIDs", default: [])

    // One-time seeding — true after the default "Important" pinboard has been created.
    static let didInstallDefaultPinboards = Key<Bool>("didInstallDefaultPinboards", default: false)
}
