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

    /// 指定ページに属する配置（sortIndex順）
    public func placements(onPage pageIndex: Int) -> [PlacementEntity] {
        orderedPlacements.filter { $0.pageIndex == pageIndex }
    }

    public func page(at index: Int) -> PageEntity? {
        pages.first { $0.index == index }
    }

    /// このプロジェクトはXタイムライン合成ビューで編集するか
    public var isXPost: Bool {
        if case .some(.x) = platformPreset { return true }
        return false
    }

    /// 末尾にページを追加する（アスペクト・背景は最後のページを引き継ぐ）
    public mutating func appendPage() {
        let template = orderedPages.last
        pages.append(PageEntity(
            index: (template?.index ?? -1) + 1,
            aspect: template?.aspect ?? AspectRatio(width: 4, height: 5),
            background: template?.background ?? .plainWhite
        ))
    }

    /// ページを削除し、そのページの配置も一緒に消す。後続ページのindexは詰める。
    /// 最後の1ページは削除できない。
    public mutating func removePage(at index: Int) {
        guard pages.count > 1, page(at: index) != nil else { return }
        pages.removeAll { $0.index == index }
        placements.removeAll { $0.pageIndex == index }
        for i in pages.indices where pages[i].index > index {
            pages[i].index -= 1
        }
        for i in placements.indices where placements[i].pageIndex > index {
            placements[i].pageIndex -= 1
        }
    }
}
