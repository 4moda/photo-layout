import UIKit
import PhotoLayoutCore

/// PreviewImageProvidingの実装。各配置のフル画像（sourceRect未適用）を
/// ImageIODecoder（書き出しと同一実装）で縮小デコードして供給する。
/// クロップの解釈はCanvasRenderViewがDrawCommand.sourceRectから行う。
final class PreviewImageProvider: PreviewImageProviding {
    private let decoder: ImageIODecoder
    private let previewMaxPixel = 2048

    init(decoder: ImageIODecoder) {
        self.decoder = decoder
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
