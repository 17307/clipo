import Foundation
import SwiftData

@Model
final class ClipContent {
    var type: String = ""
    var value: Data?

    @Relationship
    var item: ClipItem?

    init(type: String, value: Data? = nil) {
        self.type = type
        self.value = value
    }
}
