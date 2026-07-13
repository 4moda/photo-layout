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
    /// 所属ページ（PageEntity.index）。X複数枚のような異アスペクトページ構成で必須。
    /// カルーセルのまたがり配置（フェーズ5）はアンカーページ＋destRectのはみ出しで表現する
    public var pageIndex: Int
    /// テンプレートのどのスロットに入っているか（PageEntity.slots のindex）。
    /// nil = スロット非拘束の自由配置。スロット拘束の配置は空スロット判定・当てはめの対象
    public var slotIndex: Int?
    public var photo: PhotoRef
    /// 元画像に対する正規化(0..1)クロップ矩形（CLAUDE.md ルール3）
    public var cropRect: LayoutRect
    /// 写真の表示矩形。スプレッド座標系（x=0..1が1ページ目、1..2が2ページ目…、y=0..1）。
    /// 枠（フレーム）はこの矩形に付く
    public var destRect: LayoutRect
    /// クロップ窓内でサンプリングする画像の回転角度（度数法、時計回り、クロップ窓の中心軸）。
    /// destRect（枠）自体は回転しない。デフォルト0＝回転なし（既存データの読み込み値）
    public var cropRotation: Double
    /// nilならProject.defaultPhotoFrameを使う
    public var frameOverride: PhotoFrameStyle?
    /// ロック中はジオメトリ操作（移動/拡縮/クロップ突入）と削除を禁止する。
    /// 重なり順変更・枠スタイル変更はロック対象外（許可し続ける）
    public var isLocked: Bool

    public init(
        id: UUID = UUID(),
        sortIndex: Int,
        pageIndex: Int = 0,
        slotIndex: Int? = nil,
        photo: PhotoRef,
        cropRect: LayoutRect = .unit,
        destRect: LayoutRect,
        cropRotation: Double = 0,
        frameOverride: PhotoFrameStyle? = nil,
        isLocked: Bool = false
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.pageIndex = pageIndex
        self.slotIndex = slotIndex
        self.photo = photo
        self.cropRect = cropRect
        self.destRect = destRect
        self.cropRotation = cropRotation
        self.frameOverride = frameOverride
        self.isLocked = isLocked
    }

    /// ロック中に禁止するジオメトリ操作（ドラッグ・ピンチ・角/辺ハンドル・クロップ突入）を
    /// 行ってよいか。`PlacementGesture`自体は状態を持たない純粋計算のままとし、
    /// 呼び出し側（ViewModel）が各`PlacementGesture.*`呼び出し前にこれを見てガードする。
    public var allowsGeometryGesture: Bool { !isLocked }
}
