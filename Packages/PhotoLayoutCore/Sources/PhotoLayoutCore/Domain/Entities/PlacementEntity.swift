import Foundation

/// 写真1枚の配置。ページの子ではなくプロジェクト直下に置き、
/// destRectは「同一アスペクトのページを横に連結したスプレッド座標系」で表現する。
/// これにより1ページ内配置もカルーセルのまたがり配置も同じ型で扱える。
public struct PlacementEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// 表示順・重なり順。SwiftDataの配列順序に依存しない明示的な並び順（CLAUDE.md ルール6）
    public var sortIndex: Int
    public var photo: PhotoRef
    /// 元画像に対する正規化(0..1)クロップ矩形（CLAUDE.md ルール3）
    public var cropRect: LayoutRect
    public var contentMode: ContentMode
    /// スプレッド座標系での配置先。x=0..1が1ページ目、1..2が2ページ目…、y=0..1
    public var destRect: LayoutRect
    /// nilならProject.defaultPhotoFrameを使う
    public var frameOverride: PhotoFrameStyle?

    public init(
        id: UUID = UUID(),
        sortIndex: Int,
        photo: PhotoRef,
        cropRect: LayoutRect = .unit,
        contentMode: ContentMode = .fill,
        destRect: LayoutRect,
        frameOverride: PhotoFrameStyle? = nil
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.photo = photo
        self.cropRect = cropRect
        self.contentMode = contentMode
        self.destRect = destRect
        self.frameOverride = frameOverride
    }
}
