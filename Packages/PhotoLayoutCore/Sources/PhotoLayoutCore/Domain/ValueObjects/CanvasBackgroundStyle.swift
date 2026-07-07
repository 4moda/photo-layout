/// ページ全体の背景と余白。余白は出力解像度の短辺に対する比率。
public struct CanvasBackgroundStyle: Hashable, Codable, Sendable {
    public var color: LayoutColor
    public var margins: EdgeInsetsRatio

    public init(color: LayoutColor, margins: EdgeInsetsRatio) {
        self.color = color
        self.margins = margins
    }

    public static let plainWhite = CanvasBackgroundStyle(color: .white, margins: .zero)
}
