import UIKit
import PhotoLayoutCore

/// PreviewImageProvidingの実装。RenderPlanBuilderでsourceRectを確定させてから
/// ImageIODecoder（書き出しと同一実装）でクロップ済み画像を生成する。
final class PreviewImageProvider: PreviewImageProviding {
    private let decoder: ImageIODecoder
    private let previewMaxPixel = 2048

    init(decoder: ImageIODecoder) {
        self.decoder = decoder
    }

    func previewImages(project: ProjectEntity) async -> [UUID: UIImage] {
        guard let page = project.orderedPages.first else { return [:] }
        // sourceRectはサイズに対して不変（相似）なので、名目サイズでプランを作ればよい
        let nominal = LayoutSize(width: 1000 * page.aspect.ratio, height: 1000)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: project.orderedPlacements,
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: nominal
        )
        var images: [UUID: UIImage] = [:]
        for command in plan {
            if case .drawImage(let placementID, let photo, let sourceRect, _, _) = command {
                if let cgImage = decoder.cgImage(
                    photo: photo, sourceRect: sourceRect, maxPixelSize: previewMaxPixel
                ) {
                    images[placementID] = UIImage(cgImage: cgImage)
                }
            }
        }
        return images
    }
}
