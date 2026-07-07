/// 上下左右の余白。出力解像度の短辺（referenceDimension）に対する比率で保持する。
/// px化はRenderPlanBuilder内でのみ行う（CLAUDE.md ルール4）。
public struct EdgeInsetsRatio: Hashable, Codable, Sendable {
    public var top: Double
    public var bottom: Double
    public var leading: Double
    public var trailing: Double

    public init(top: Double, bottom: Double, leading: Double, trailing: Double) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }

    public init(uniform: Double) {
        self.init(top: uniform, bottom: uniform, leading: uniform, trailing: uniform)
    }

    public static let zero = EdgeInsetsRatio(uniform: 0)
}
