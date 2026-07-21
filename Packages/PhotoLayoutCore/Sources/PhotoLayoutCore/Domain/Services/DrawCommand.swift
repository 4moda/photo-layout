import Foundation

/// プレビュー（SwiftUI Canvas）と書き出し（CGContext）が共通に解釈する描画命令。
/// ジオメトリはすべてRenderPlanBuilderが確定済みのピクセル値で持ち、
/// 解釈側（レンダラ）は計算を一切行わない — プレビューと書き出しの一致を構造的に保証する。
public enum DrawCommand: Equatable, Sendable {
    /// rect（px）を単色で塗る
    case fillRect(color: LayoutColor, rect: LayoutRect)
    /// 写真のsourceRect（元画像に対する正規化0..1、クロップ窓全体・配置領域内でのはみ出しでクリップされる前）を
    /// destRect（px、クロップ窓をそのまま置いたときの矩形・同じくクリップ前）へ写像し、destRectの中心を軸に
    /// rotationDegrees（度数法、時計回り）だけ回転させたうえで、clipRect（px、配置領域からはみ出た分を
    /// 除いた実際に見える範囲）だけ描く。destRect自体は回転しない（枠は歪まない・CLAUDE.md ルール4）。
    /// はみ出しがなければclipRect==destRect。
    case drawImage(
        placementID: UUID,
        photo: PhotoRef,
        sourceRect: LayoutRect,
        destRect: LayoutRect,
        clipRect: LayoutRect,
        rotationDegrees: Double,
        cornerRadiusPx: Double
    )
    /// rect（px、線の中心線）に沿って枠線を描く
    case strokeBorder(color: LayoutColor, lineWidthPx: Double, cornerRadiusPx: Double, rect: LayoutRect)
    /// テキストを(originX, originY)（px、左上基準）から描く。フォントはシステムフォント固定
    /// （種別の選択はスコープ外）。ジオメトリ（位置・フォントサイズ）はRenderPlanBuilderが
    /// 比率からpx化済みで、レンダラ側は計算しない
    case drawText(text: String, originX: Double, originY: Double, fontSizePx: Double, color: LayoutColor)
}
