import Foundation

/// プレビュー（SwiftUI Canvas）と書き出し（CGContext）が共通に解釈する描画命令。
/// ジオメトリはすべてRenderPlanBuilderが確定済みのピクセル値で持ち、
/// 解釈側（レンダラ）は計算を一切行わない — プレビューと書き出しの一致を構造的に保証する。
public enum DrawCommand: Equatable, Sendable {
    /// rect（px）を単色で塗る
    case fillRect(color: LayoutColor, rect: LayoutRect)
    /// 写真のsourceRect（元画像に対する正規化0..1）をdestRect（px）へ描く
    case drawImage(
        placementID: UUID,
        photo: PhotoRef,
        sourceRect: LayoutRect,
        destRect: LayoutRect,
        cornerRadiusPx: Double
    )
    /// rect（px、線の中心線）に沿って枠線を描く
    case strokeBorder(color: LayoutColor, lineWidthPx: Double, cornerRadiusPx: Double, rect: LayoutRect)
}
