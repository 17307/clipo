import Foundation
import SwiftData

@Model
final class Pinboard {
    var id: UUID = UUID()
    var name: String = ""
    var accentColorHex: String = "#FF6A3D"
    var order: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \ClipItem.pinboard)
    var items: [ClipItem] = []

    init(name: String, accentColorHex: String = "#FF6A3D", order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.accentColorHex = accentColorHex
        self.order = order
    }
}
