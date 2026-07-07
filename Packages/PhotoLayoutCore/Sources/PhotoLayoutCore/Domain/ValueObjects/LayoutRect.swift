/// 座標系に依存しない矩形。正規化(0..1)クロップ空間・スプレッド空間・ピクセル空間のすべてで使う。
/// CoreGraphicsのCGRectはDomainでは使わない（Apple framework非依存の原則）。
public struct LayoutRect: Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// 正規化空間全体 (0,0,1,1)
    public static let unit = LayoutRect(x: 0, y: 0, width: 1, height: 1)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var aspectRatio: Double { width / height }

    public func contains(_ other: LayoutRect, tolerance: Double = 1e-9) -> Bool {
        other.minX >= minX - tolerance
            && other.minY >= minY - tolerance
            && other.maxX <= maxX + tolerance
            && other.maxY <= maxY + tolerance
    }

    /// contentのアスペクト比を保ったまま、この矩形に全体が収まる最大の矩形（中央寄せ）。
    /// fitモード（マット仕上げ：切らずに余白で収める）の基礎計算。
    public func fitting(_ content: AspectRatio) -> LayoutRect {
        scaled(content, by: min(width / content.width, height / content.height))
    }

    /// contentのアスペクト比を保ったまま、この矩形を覆う最小の矩形（中央寄せ）。
    /// fillモード（切ってはめる）の基礎計算。
    public func filling(_ content: AspectRatio) -> LayoutRect {
        scaled(content, by: max(width / content.width, height / content.height))
    }

    private func scaled(_ content: AspectRatio, by scale: Double) -> LayoutRect {
        let w = content.width * scale
        let h = content.height * scale
        return LayoutRect(x: midX - w / 2, y: midY - h / 2, width: w, height: h)
    }

    /// 中心を保ったまま全体を等倍で拡縮した矩形
    public func scaled(by factor: Double) -> LayoutRect {
        let w = width * factor
        let h = height * factor
        return LayoutRect(x: midX - w / 2, y: midY - h / 2, width: w, height: h)
    }

    public func isApproximatelyEqual(to other: LayoutRect, tolerance: Double = 1e-6) -> Bool {
        abs(x - other.x) < tolerance
            && abs(y - other.y) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}
