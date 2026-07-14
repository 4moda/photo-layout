import Foundation

/// 写真窓（スロット）の仕様 — 構図の最小単位。
/// ページ直付きの型枠（`PageEntity.slots`）と、将来の装飾枠（フィルム風・フォトフレーム風の
/// 「動かせる複数窓オブジェクト」= FrameInstance構想）の窓（aperture）が共有する語彙。
/// 座標は親（ページ配置領域、または将来の枠のdestRect）に対するローカル正規化(0..1)。
///
/// 将来キーを足すときは `decodeIfPresent`＋既定値のカスタムデコードにして、
/// それ以前に保存されたデータを読めるようにする（スキーマ進化の規則）。
public struct SlotSpec: Hashable, Codable, Sendable {
    public var rect: LayoutRect
    /// 窓のクリップ形状。将来 円形・角丸等を追加する（描画はDrawCommandの語彙拡張で対応）
    public var clipShape: ClipShape
    /// 窓ごとの縁スタイル。nil = プロジェクト既定（`defaultPhotoFrame`）に従う
    public var frameStyle: PhotoFrameStyle?

    public enum ClipShape: String, Hashable, Codable, Sendable {
        case rectangle
    }

    public init(rect: LayoutRect, clipShape: ClipShape = .rectangle, frameStyle: PhotoFrameStyle? = nil) {
        self.rect = rect
        self.clipShape = clipShape
        self.frameStyle = frameStyle
    }

    /// テンプレート一致判定などで使う近似比較（rectは許容誤差つき、形状・縁は完全一致）
    public func isApproximatelyEqual(to other: SlotSpec, tolerance: Double = 1e-6) -> Bool {
        rect.isApproximatelyEqual(to: other.rect, tolerance: tolerance)
            && clipShape == other.clipShape
            && frameStyle == other.frameStyle
    }
}
