import Photos
import PhotoLayoutCore

/// PhotoLibrarySavingの実装。追加のみ権限（NSPhotoLibraryAddUsageDescription）で保存する。
final class PHPhotoLibrarySaveAdapter: PhotoLibrarySaving {
    func save(imageData: Data) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: imageData, options: nil)
        }
    }
}
