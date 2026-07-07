import Foundation

/// 書き出し単位となる1ページ。X複数枚投稿の各画像、カルーセルの各スライドに対応する。
public struct PageEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// 投稿順＝書き出し順。明示的なindexで管理（CLAUDE.md ルール6）
    public var index: Int
    public var aspect: AspectRatio
    public var background: CanvasBackgroundStyle

    public init(
        id: UUID = UUID(),
        index: Int,
        aspect: AspectRatio,
        background: CanvasBackgroundStyle = .plainWhite
    ) {
        self.id = id
        self.index = index
        self.aspect = aspect
        self.background = background
    }
}
