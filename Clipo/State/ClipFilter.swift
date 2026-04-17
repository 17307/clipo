import Foundation
import SwiftUI

/// A top-bar tab selector for the clipboard carousel.
enum ClipFilter: Hashable {
    case history
    case images
    case files
    case pinboard(UUID)
}

extension ClipFilter {
    var builtInTitle: String? {
        switch self {
        case .history: return "History"
        case .images:  return "Images"
        case .files:   return "Files"
        case .pinboard: return nil
        }
    }

    var builtInIcon: String? {
        switch self {
        case .history: return "clock"
        case .images:  return "photo"
        case .files:   return "doc.fill"
        case .pinboard: return nil
        }
    }

    var builtInAccent: Color? {
        switch self {
        case .history: return nil     // use user's theme accent
        case .images:  return .blue
        case .files:   return .indigo
        case .pinboard: return nil    // use pinboard's color
        }
    }
}
