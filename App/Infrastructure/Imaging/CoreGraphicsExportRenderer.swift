import UIKit
import PhotoLayoutCore

/// ImageExportingの実装。目標ピクセルサイズちょうど・scale=1のコンテキストで
/// DrawCommandを解釈する（CLAUDE.md ルール2: ImageRenderer.scale方式は使用禁止）。
final class CoreGraphicsExportRenderer: ImageExporting {
    private let decoder: ImageIODecoder

    init(decoder: ImageIODecoder) {
        self.decoder = decoder
    }

    func render(plan: [DrawCommand], pixelSize: LayoutSize, format: ExportFormat) async throws -> Data {
        let size = CGSize(width: pixelSize.width, height: pixelSize.height)
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1 // 1pt = 1px を保証
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: rendererFormat)

        let image = renderer.image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .high

            for command in plan {
                switch command {
                case .fillRect(let color, let rect):
                    cg.setFillColor(uiColor(color).cgColor)
                    cg.fill(cgRect(rect))

                case .drawImage(_, let photo, let sourceRect, let destRect, let clipRect, let rotationDegrees, let cornerRadiusPx):
                    // 1枚ごとにデコード→描画→解放し、複数枚でもメモリを積み上げない
                    autoreleasepool {
                        let dest = cgRect(destRect)
                        let clip = cgRect(clipRect)
                        cg.saveGState()
                        UIBezierPath(roundedRect: clip, cornerRadius: cornerRadiusPx).addClip()

                        if rotationDegrees == 0 {
                            // 回転なし: 従来どおり見える範囲だけをsourceRectから絞り込みデコードし、
                            // clipへ直接描く（はみ出した分をデコード・描画しない効率経路）。
                            // destRectはRenderPlanBuilderがwidth/height>0を保証済み
                            let visibleSource = LayoutRect(
                                x: sourceRect.x + (clipRect.x - destRect.x) / destRect.width * sourceRect.width,
                                y: sourceRect.y + (clipRect.y - destRect.y) / destRect.height * sourceRect.height,
                                width: clipRect.width / destRect.width * sourceRect.width,
                                height: clipRect.height / destRect.height * sourceRect.height
                            )
                            if let cgImage = decoder.cgImage(photo: photo, sourceRect: visibleSource, maxPixelSize: nil) {
                                UIImage(cgImage: cgImage).draw(in: clip)
                            }
                        } else {
                            // 回転あり: クロップ窓全体をデコードし、destRectの中心を軸にCTMを回転させてから
                            // 描く（destRect自体は回転しない・クリップ済みのclip内だけが実際に残る）
                            if let cgImage = decoder.cgImage(photo: photo, sourceRect: sourceRect, maxPixelSize: nil) {
                                cg.translateBy(x: dest.midX, y: dest.midY)
                                cg.rotate(by: CGFloat(rotationDegrees * .pi / 180))
                                cg.translateBy(x: -dest.midX, y: -dest.midY)
                                UIImage(cgImage: cgImage).draw(in: dest)
                            }
                        }
                        cg.restoreGState()
                    }

                case .strokeBorder(let color, let lineWidthPx, let cornerRadiusPx, let rect):
                    let path = UIBezierPath(roundedRect: cgRect(rect), cornerRadius: cornerRadiusPx)
                    path.lineWidth = lineWidthPx
                    uiColor(color).setStroke()
                    path.stroke()
                }
            }
        }

        let data: Data?
        switch format {
        case .jpeg(let quality):
            data = image.jpegData(compressionQuality: quality)
        case .png:
            data = image.pngData()
        }
        guard let data, !data.isEmpty else { throw ExportError.encodingFailed }
        return data
    }

    private func cgRect(_ rect: LayoutRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private func uiColor(_ color: LayoutColor) -> UIColor {
        UIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}
