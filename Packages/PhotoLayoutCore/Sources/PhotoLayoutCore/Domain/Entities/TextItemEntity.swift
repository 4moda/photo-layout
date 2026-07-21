import Foundation

/// ページに置く短いテキスト1件（フィルム銘柄・撮影日・ひとこと等）。
/// 写真と同じく「比率で保持しpx化は描画直前のみ」の規約に揃える（CLAUDE.md ルール4）。
public struct TextItemEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// 所属ページ（PageEntity.index）
    public var pageIndex: Int
    /// 重なり順。SwiftDataの配列順序に依存しない明示的な並び順（CLAUDE.md ルール6）
    public var sortIndex: Int
    public var content: String
    /// 配置領域（余白を除いた領域）に対する正規化(0..1)原点位置（テキストの左上）
    public var x: Double
    public var y: Double
    /// 出力解像度の短辺（`LayoutSize.referenceDimension`）に対する比率のフォントサイズ。
    /// `PhotoFrameStyle.borderWidthRatio`等と同じ規約。px化は`RenderPlanBuilder`のみで行う
    public var fontSizeRatio: Double
    public var color: LayoutColor

    /// 追加直後の既定フォントサイズ比率
    public static let defaultFontSizeRatio: Double = 0.04

    public init(
        id: UUID = UUID(),
        pageIndex: Int = 0,
        sortIndex: Int,
        content: String,
        x: Double,
        y: Double,
        fontSizeRatio: Double = TextItemEntity.defaultFontSizeRatio,
        color: LayoutColor = .black
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.sortIndex = sortIndex
        self.content = content
        self.x = x
        self.y = y
        self.fontSizeRatio = fontSizeRatio
        self.color = color
    }
}
