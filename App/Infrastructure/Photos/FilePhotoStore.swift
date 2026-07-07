import Foundation
import ImageIO
import PhotoLayoutCore

enum PhotoStoreError: Error {
    case invalidImage
}

/// PhotoStoringの実装。写真データをSourceImages/へコピーし、
/// ImageIOでEXIF向き適用後のピクセル寸法を読み取ってPhotoRefを返す。
final class FilePhotoStore: PhotoStoring {
    private let directory: URL

    init(directory: URL = SourceImagesLocation.default) {
        self.directory = directory
    }

    func store(imageData: Data) async throws -> PhotoRef {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw PhotoStoreError.invalidImage
        }
        // EXIF orientation 5..8 は90度系回転 → 実表示上の縦横が入れ替わる
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let isRotated = orientation >= 5

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileName = UUID().uuidString
        try imageData.write(to: directory.appendingPathComponent(fileName))

        return PhotoRef(
            fileName: fileName,
            pixelWidth: isRotated ? height : width,
            pixelHeight: isRotated ? width : height
        )
    }
}
