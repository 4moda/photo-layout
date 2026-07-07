/// 写真1枚ごとのフレーム。太さ・角丸は出力解像度の短辺に対する比率。
public struct PhotoFrameStyle: Hashable, Codable, Sendable {
    public var borderColor: LayoutColor
    public var borderWidthRatio: Double
    public var cornerRadiusRatio: Double

    public init(borderColor: LayoutColor, borderWidthRatio: Double, cornerRadiusRatio: Double) {
        self.borderColor = borderColor
        self.borderWidthRatio = borderWidthRatio
        self.cornerRadiusRatio = cornerRadiusRatio
    }

    public static let none = PhotoFrameStyle(borderColor: .clear, borderWidthRatio: 0, cornerRadiusRatio: 0)
}
