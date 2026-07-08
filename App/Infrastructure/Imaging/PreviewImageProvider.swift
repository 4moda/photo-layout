import UIKit
import PhotoLayoutCore

/// PreviewImageProvidingの実装。各配置のフル画像（sourceRect未適用）を
/// ImageIODecoder（書き出しと同一実装）で縮小デコードして供給する。
/// クロップの解釈はCanvasRenderViewがDrawCommand.sourceRectから行う。
final class PreviewImageProvider: PreviewImageProviding {
    private let decoder: ImageIODecoder
    private let previewMaxPixel: Int

    /// - Parameter maxPixelSize: デコード上限（長辺px）。一覧サムネイルは小さく指定してメモリと速度を守る
    init(decoder: ImageIODecoder, maxPixelSize: Int = 2048) {
        self.decoder = decoder
        self.previewMaxPixel = maxPixelSize
    }

    func previewImages(project: ProjectEntity) async -> [UUID: UIImage] {
        var images: [UUID: UIImage] = [:]
        for placement in project.placements {
            if let cgImage = decoder.cgImage(
                photo: placement.photo, sourceRect: .unit, maxPixelSize: previewMaxPixel
            ) {
                images[placement.id] = UIImage(cgImage: cgImage)
            }
        }
        return images
    }
}
