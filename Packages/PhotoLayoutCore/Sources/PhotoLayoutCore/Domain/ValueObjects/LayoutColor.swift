/// RGBA色（各成分0..1）。UIColor/SwiftUI.Colorへの変換はPresentation/Infrastructure側で行う。
public struct LayoutColor: Hashable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = LayoutColor(red: 1, green: 1, blue: 1)
    public static let black = LayoutColor(red: 0, green: 0, blue: 0)
    public static let clear = LayoutColor(red: 0, green: 0, blue: 0, alpha: 0)
}
