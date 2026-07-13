import Foundation
import SwiftData

/// FolderEntityの永続化表現。
@Model
final class FolderModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
