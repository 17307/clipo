import Foundation
import SwiftData

@MainActor
final class Storage {
    static let shared = Storage()

    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    private let url = URL.applicationSupportDirectory.appending(path: "Clipo/Storage.sqlite")

    init() {
        let config = ModelConfiguration(url: url)
        do {
            container = try ModelContainer(
                for: ClipItem.self, ClipContent.self, Pinboard.self,
                configurations: config
            )
        } catch {
            fatalError("Cannot load Clipo database: \(error.localizedDescription)")
        }
    }
}
