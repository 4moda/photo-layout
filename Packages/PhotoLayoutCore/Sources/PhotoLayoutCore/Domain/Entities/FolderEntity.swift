import Foundation

/// プロジェクトをグルーピングするフォルダ。入れ子・多重所属は非対応（v1）。
public struct FolderEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
