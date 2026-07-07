import Foundation

/// 取り込み写真のローカルコピー置き場。FilePhotoStoreとImageIODecoderで共有する。
enum SourceImagesLocation {
    static var `default`: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SourceImages", isDirectory: true)
    }
}
