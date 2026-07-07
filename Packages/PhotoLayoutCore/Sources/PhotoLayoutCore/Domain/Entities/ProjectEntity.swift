import Foundation

/// 1つの投稿準備プロジェクト（下書き）。
public struct ProjectEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var title: String?
    public var platformPreset: PlatformPreset?
    public var pages: [PageEntity]
    public var placements: [PlacementEntity]
    public var defaultPhotoFrame: PhotoFrameStyle
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        platformPreset: PlatformPreset? = nil,
        pages: [PageEntity] = [],
        placements: [PlacementEntity] = [],
        defaultPhotoFrame: PhotoFrameStyle = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.platformPreset = platformPreset
        self.pages = pages
        self.placements = placements
        self.defaultPhotoFrame = defaultPhotoFrame
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// index順に整列したページ列（保存順に依存しないアクセス用）
    public var orderedPages: [PageEntity] {
        pages.sorted { $0.index < $1.index }
    }

    /// sortIndex順に整列した配置列
    public var orderedPlacements: [PlacementEntity] {
        placements.sorted { $0.sortIndex < $1.sortIndex }
    }
}
