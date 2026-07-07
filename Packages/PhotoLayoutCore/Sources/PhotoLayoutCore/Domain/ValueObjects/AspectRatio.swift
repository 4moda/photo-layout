/// 幅:高さで表すアスペクト比。
public struct AspectRatio: Hashable, Codable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        precondition(width > 0 && height > 0, "AspectRatio requires positive dimensions")
        self.width = width
        self.height = height
    }

    /// 横/縦の比。1より大きければ横長。
    public var ratio: Double { width / height }

    public var isPortrait: Bool { height > width }
    public var isLandscape: Bool { width > height }
    public var isSquare: Bool { width == height }
}
