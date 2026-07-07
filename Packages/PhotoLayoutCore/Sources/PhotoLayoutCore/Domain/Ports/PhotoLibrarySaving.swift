import Foundation

/// 画像データをユーザーの写真ライブラリへ保存するPort（追加のみ権限）。
public protocol PhotoLibrarySaving: Sendable {
    func save(imageData: Data) async throws
}
