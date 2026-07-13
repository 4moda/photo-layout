import Foundation

/// 1つの投稿準備プロジェクト（下書き）。
public struct ProjectEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var title: String?
    public var platformPreset: PlatformPreset?
    public var pages: [PageEntity]
    public var placements: [PlacementEntity]
    public var defaultPhotoFrame: PhotoFrameStyle
    /// 所属フォルダ。nil = 未分類（既存データ・入れ子非対応の前提）
    public var folderID: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String? = nil,
        platformPreset: PlatformPreset? = nil,
        pages: [PageEntity] = [],
        placements: [PlacementEntity] = [],
        defaultPhotoFrame: PhotoFrameStyle = .none,
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.platformPreset = platformPreset
        self.pages = pages
        self.placements = placements
        self.defaultPhotoFrame = defaultPhotoFrame
        self.folderID = folderID
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

    /// 指定位置にページを挿入する。アスペクト・背景は直前のページ（先頭挿入なら直後のページ）を引き継ぐ。
    /// 挿入位置以降のページindexと配置のpageIndexは後ろへずれる。
    public mutating func insertPage(at index: Int) {
        let clamped = min(max(index, 0), pages.count)
        let template = page(at: clamped - 1) ?? page(at: clamped)
        for i in pages.indices where pages[i].index >= clamped {
            pages[i].index += 1
        }
        for i in placements.indices where placements[i].pageIndex >= clamped {
            placements[i].pageIndex += 1
        }
        pages.append(PageEntity(
            index: clamped,
            aspect: template?.aspect ?? AspectRatio(width: 4, height: 5),
            background: template?.background ?? .plainWhite
        ))
    }

    /// ページの並び替え。fromの位置のページをtoの位置へ動かし、配置のpageIndexも追随する。
    /// toは「fromを取り除いた後の最終位置」
    public mutating func movePage(from: Int, to: Int) {
        let count = pages.count
        guard from != to, (0..<count).contains(from), (0..<count).contains(to) else { return }
        var order = Array(0..<count)
        let moved = order.remove(at: from)
        order.insert(moved, at: to)
        var mapping: [Int: Int] = [:]
        for (newIndex, oldIndex) in order.enumerated() {
            mapping[oldIndex] = newIndex
        }
        for i in pages.indices {
            pages[i].index = mapping[pages[i].index] ?? pages[i].index
        }
        for i in placements.indices {
            placements[i].pageIndex = mapping[placements[i].pageIndex] ?? placements[i].pageIndex
        }
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
