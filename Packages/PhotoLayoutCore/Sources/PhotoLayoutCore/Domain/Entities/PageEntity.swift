import Foundation

/// 書き出し単位となる1ページ。X複数枚投稿の各画像、カルーセルの各スライドに対応する。
public struct PageEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// 投稿順＝書き出し順。明示的なindexで管理（CLAUDE.md ルール6）
    public var index: Int
    public var aspect: AspectRatio
    public var background: CanvasBackgroundStyle
    /// このスライドに敷いたテンプレートのスロット矩形（配置領域の正規化0..1）。
    /// nil = 型枠なしの自由キャンバス。非nilなら「空スロット」が存在でき、写真を当てはめる。
    public var slots: [LayoutRect]?

    public init(
        id: UUID = UUID(),
        index: Int,
        aspect: AspectRatio,
        background: CanvasBackgroundStyle = .plainWhite,
        slots: [LayoutRect]? = nil
    ) {
        self.id = id
        self.index = index
        self.aspect = aspect
        self.background = background
        self.slots = slots
    }

    /// 余白を差し引いた配置領域の実ピクセルアスペクト（サイズに依存しない）。
    /// 余白は短辺基準の比率なので、名目サイズ（w=ratio, h=1）で計算できる。
    public var contentAspect: Double {
        let width = aspect.ratio
        let height = 1.0
        let ref = min(width, height)
        let contentWidth = width - (background.margins.leading + background.margins.trailing) * ref
        let contentHeight = height - (background.margins.top + background.margins.bottom) * ref
        guard contentWidth > 0, contentHeight > 0 else { return aspect.ratio }
        return contentWidth / contentHeight
    }
}
