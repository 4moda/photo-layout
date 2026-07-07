import Foundation
import ImageIO
import CoreGraphics
import PhotoLayoutCore

/// 写真ファイル→（EXIF向き適用済み・必要ならクロップ済み）CGImageの供給。
/// DrawCommand.sourceRectの解釈はプレビューも書き出しもこの1実装を共有する（二重実装禁止）。
final class ImageIODecoder: Sendable {
    private let directory: URL

    init(directory: URL = SourceImagesLocation.default) {
        self.directory = directory
    }

    /// - Parameters:
    ///   - photo: 対象写真
    ///   - sourceRect: 元画像に対する正規化(0..1)クロップ。unitなら全体
    ///   - maxPixelSize: デコード上限（長辺px）。nilなら原寸
    func cgImage(photo: PhotoRef, sourceRect: LayoutRect, maxPixelSize: Int?) -> CGImage? {
        let url = directory.appendingPathComponent(photo.fileName)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // EXIF向きを適用してデコードする（PhotoRefの縦横と一致させる）
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        // クロップ後に必要な解像度から、デコード時点の縮小上限を逆算する
        // （フルデコード→縮小のメモリ浪費を避ける。CLAUDE.md リスク3対策）
        if let maxPixelSize {
            let cropFraction = max(min(sourceRect.width, sourceRect.height), 0.0001)
            let decodeMax = min(
                Double(max(photo.pixelWidth, photo.pixelHeight)),
                Double(maxPixelSize) / cropFraction
            )
            options[kCGImageSourceThumbnailMaxPixelSize] = decodeMax
        } else {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(photo.pixelWidth, photo.pixelHeight)
        }

        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        if sourceRect == .unit { return decoded }

        let pixelRect = CGRect(
            x: (sourceRect.x * Double(decoded.width)).rounded(.down),
            y: (sourceRect.y * Double(decoded.height)).rounded(.down),
            width: (sourceRect.width * Double(decoded.width)).rounded(.down),
            height: (sourceRect.height * Double(decoded.height)).rounded(.down)
        )
        return decoded.cropping(to: pixelRect) ?? decoded
    }
}
