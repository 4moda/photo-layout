import SwiftUI
import PhotoLayoutCore

/// DrawCommandをSwiftUI Canvasで解釈するプレビュー。
/// ジオメトリ計算はRenderPlanBuilderに完全に委譲し、ここでは一切計算しない
/// （書き出しとの一致を構造的に保証する。CLAUDE.md ルール5）。
struct CanvasRenderView: View {
    let page: PageEntity
    let placements: [PlacementEntity]
    let defaultFrame: PhotoFrameStyle
    /// 配置ID→フル画像（sourceRect未適用）。クロップはsourceRectの写像で描画時に適用する
    let images: [UUID: UIImage]

    var body: some View {
        Canvas { context, size in
            let plan = RenderPlanBuilder.build(
                page: page,
                placements: placements,
                defaultFrame: defaultFrame,
                pagePixelSize: LayoutSize(width: size.width, height: size.height)
            )
            for command in plan {
                switch command {
                case .fillRect(let color, let rect):
                    context.fill(Path(cgRect(rect)), with: .color(swiftUIColor(color)))

                case .drawImage(let placementID, _, let sourceRect, let destRect, let clipRect, let rotationDegrees, let cornerRadiusPx):
                    guard let uiImage = images[placementID] else { break }
                    // sourceRect（元画像の正規化部分矩形・クロップ窓全体）がdestRectへ写るよう、
                    // フル画像をdestRectより大きい矩形へ描き、clipRect（見える範囲）でクリップする。
                    // 書き出し側（CoreGraphicsExportRenderer）と同じ写像の別実装。
                    let dest = cgRect(destRect)
                    let clip = cgRect(clipRect)
                    let fullWidth = dest.width / sourceRect.width
                    let fullHeight = dest.height / sourceRect.height
                    let fullRect = CGRect(
                        x: dest.minX - sourceRect.x * fullWidth,
                        y: dest.minY - sourceRect.y * fullHeight,
                        width: fullWidth,
                        height: fullHeight
                    )
                    var imageContext = context
                    imageContext.clip(to: Path(roundedRect: clip, cornerRadius: cornerRadiusPx))
                    if rotationDegrees != 0 {
                        // destRect（枠）自体は回転させず、その中心を軸にサンプリングする画素だけ回す
                        let center = CGPoint(x: dest.midX, y: dest.midY)
                        imageContext.translateBy(x: center.x, y: center.y)
                        imageContext.rotate(by: .degrees(rotationDegrees))
                        imageContext.translateBy(x: -center.x, y: -center.y)
                    }
                    imageContext.draw(Image(uiImage: uiImage), in: fullRect)

                case .strokeBorder(let color, let lineWidthPx, let cornerRadiusPx, let rect):
                    context.stroke(
                        Path(roundedRect: cgRect(rect), cornerRadius: cornerRadiusPx),
                        with: .color(swiftUIColor(color)),
                        lineWidth: lineWidthPx
                    )
                }
            }
        }
        .aspectRatio(page.aspect.ratio, contentMode: .fit)
    }

    private func cgRect(_ rect: LayoutRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private func swiftUIColor(_ color: LayoutColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}
