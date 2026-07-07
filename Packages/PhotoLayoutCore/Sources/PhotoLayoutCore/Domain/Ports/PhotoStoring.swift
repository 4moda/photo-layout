import Foundation

/// 写真バイト列をアプリ管理領域へ保存し、参照を返すPort。
/// 実装（Infrastructure）はImageIOでピクセル寸法（EXIF向き適用後）を読み取る。
public protocol PhotoStoring: Sendable {
    func store(imageData: Data) async throws -> PhotoRef
}
