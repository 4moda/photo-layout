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

                case .drawImage(_, let photo, let sourceRect, let destRect, let cornerRadiusPx):
                    // 1枚ごとにデコード→描画→解放し、複数枚でもメモリを積み上げない
                    autoreleasepool {
                        guard let cgImage = decoder.cgImage(
                            photo: photo, sourceRect: sourceRect, maxPixelSize: nil
                        ) else { return }
                        cg.saveGState()
                        let dest = cgRect(destRect)
                        if cornerRadiusPx > 0 {
                            UIBezierPath(roundedRect: dest, cornerRadius: cornerRadiusPx).addClip()
                        }
                        UIImage(cgImage: cgImage).draw(in: dest)
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
