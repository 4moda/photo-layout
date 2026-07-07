import Foundation

/// 写真1枚の配置。写真は自由変形オブジェクトであり、fill/fitのようなモードは持たない。
/// 「全面に敷く」「余白を残して置く」はすべてcropRect/destRectのジオメトリとして表現される。
///
/// 不変条件: destRectのピクセルアスペクト == cropRectのピクセルアスペクト
/// （配置ヘルパ・ジェスチャロジックが維持する。RenderPlanBuilderは防御的に正規化する）
public struct PlacementEntity: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    /// 表示順・重なり順。SwiftDataの配列順序に依存しない明示的な並び順（CLAUDE.md ルール6）
    public var sortIndex: Int
    public var photo: PhotoRef
    /// 元画像に対する正規化(0..1)クロップ矩形（CLAUDE.md ルール3）
    public var cropRect: LayoutRect
    /// 写真の表示矩形。スプレッド座標系（x=0..1が1ページ目、1..2が2ページ目…、y=0..1）。
    /// 枠（フレーム）はこの矩形に付く
    public var destRect: LayoutRect
    /// nilならProject.defaultPhotoFrameを使う
    public var frameOverride: PhotoFrameStyle?

    public init(
        id: UUID = UUID(),
        sortIndex: Int,
        photo: PhotoRef,
        cropRect: LayoutRect = .unit,
        destRect: LayoutRect,
        frameOverride: PhotoFrameStyle? = nil
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.photo = photo
        self.cropRect = cropRect
        self.destRect = destRect
        self.frameOverride = frameOverride
    }
}
