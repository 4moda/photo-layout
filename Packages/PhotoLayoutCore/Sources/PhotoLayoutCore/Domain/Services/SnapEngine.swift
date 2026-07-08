/// 配置移動中のスナップ（吸着）計算。純粋関数。
/// ページガイド（辺・中心）と他の配置の辺・中心を候補とし、
/// しきい値以内で最も近い候補へ矩形を吸着させ、表示すべきガイド線を返す。
public enum SnapEngine {
    public struct Guide: Equatable, Sendable {
        public enum Axis: Equatable, Sendable {
            case vertical    // x = position の縦線
            case horizontal  // y = position の横線
        }
        public let axis: Axis
        public let position: Double // 配置領域の正規化座標

        public init(axis: Axis, position: Double) {
            self.axis = axis
            self.position = position
        }
    }

    public struct Result: Equatable, Sendable {
        public let rect: LayoutRect
        public let guides: [Guide]
    }

    /// - Parameters:
    ///   - moving: 移動中の矩形（配置領域の正規化座標）
    ///   - others: 同一ページ内の他の配置のdestRect
    ///   - threshold: 吸着距離（正規化座標）
    public static func snap(
        moving: LayoutRect,
        others: [LayoutRect] = [],
        threshold: Double = 0.02
    ) -> Result {
        var candidatesX: [Double] = [0, 0.5, 1]
        var candidatesY: [Double] = [0, 0.5, 1]
        for other in others {
            candidatesX.append(contentsOf: [other.minX, other.midX, other.maxX])
            candidatesY.append(contentsOf: [other.minY, other.midY, other.maxY])
        }

        var rect = moving
        var guides: [Guide] = []

        if let (delta, position) = bestSnap(
            edges: [moving.minX, moving.midX, moving.maxX],
            candidates: candidatesX,
            threshold: threshold
        ) {
            rect.x += delta
            guides.append(Guide(axis: .vertical, position: position))
        }
        if let (delta, position) = bestSnap(
            edges: [moving.minY, moving.midY, moving.maxY],
            candidates: candidatesY,
            threshold: threshold
        ) {
            rect.y += delta
            guides.append(Guide(axis: .horizontal, position: position))
        }
        return Result(rect: rect, guides: guides)
    }

    /// 各辺と候補の全組合せから最小距離の吸着を選ぶ。しきい値超過ならnil。
    private static func bestSnap(
        edges: [Double],
        candidates: [Double],
        threshold: Double
    ) -> (delta: Double, position: Double)? {
        var best: (delta: Double, position: Double)?
        var bestDistance = threshold
        for edge in edges {
            for candidate in candidates {
                let distance = abs(candidate - edge)
                if distance <= bestDistance {
                    bestDistance = distance
                    best = (candidate - edge, candidate)
                }
            }
        }
        return best
    }
}
