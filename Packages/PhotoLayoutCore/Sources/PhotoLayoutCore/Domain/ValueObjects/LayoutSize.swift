/// 座標系に依存しないサイズ（ピクセル/ポイント両方で使う）。
public struct LayoutSize: Hashable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// 枠・余白の比率計算の基準となる短辺
    public var referenceDimension: Double { min(width, height) }
    public var longEdge: Double { max(width, height) }
}
