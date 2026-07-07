import SwiftUI
import PhotoLayoutCore

/// DrawCommandをSwiftUI Canvasで解釈するプレビュー。
/// ジオメトリ計算はRenderPlanBuilderに完全に委譲し、ここでは一切計算しない
/// （書き出しとの一致を構造的に保証する。CLAUDE.md ルール5）。
struct CanvasRenderView: View {
    let page: PageEntity
    let placements: [PlacementEntity]
    let defaultFrame: PhotoFrameStyle
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

                case .drawImage(let placementID, _, _, let destRect, let cornerRadiusPx):
                    guard let uiImage = images[placementID] else { break }
                    var imageContext = context
                    if cornerRadiusPx > 0 {
                        imageContext.clip(to: Path(roundedRect: cgRect(destRect), cornerRadius: cornerRadiusPx))
                    }
                    imageContext.draw(Image(uiImage: uiImage), in: cgRect(destRect))

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
