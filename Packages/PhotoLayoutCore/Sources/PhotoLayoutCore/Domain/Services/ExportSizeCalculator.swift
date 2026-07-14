import Foundation

/// 書き出し解像度の選択肢。
/// - standard: 従来どおり元画像の実解像度を優先（アップスケールしない）
/// - high: 長辺2048pxを最低保証（小さい元画像はアップスケール。SNS側の縮小・再圧縮による
///   見劣り対策で、情報量が増えるわけではない）
public enum ExportResolution: String, CaseIterable, Sendable {
    case standard
    case high

    /// この長辺px未満なら引き上げる（0は引き上げなし）
    public var minLongEdge: Double {
        switch self {
        case .standard: return 0
        case .high: return 2048
        }
    }
}

/// 書き出しピクセルサイズの決定。
/// 「元画像の実解像度を活かし、かつXの再圧縮を避ける長辺4096px以内」が原則。
public enum ExportSizeCalculator {
    public static let maxLongEdge: Double = 4096
    /// 写真が1枚もない等の場合の既定出力（短辺基準）
    public static let fallbackShortEdge: Double = 2048

    /// ページの出力ピクセルサイズを決める。
    /// 各placementのクロップ後実解像度がdestRect比率で必要とするページサイズの最大値を採用し、
    /// 長辺4096pxにクランプする（アップスケールはしない方針だが、最低でもfallbackは確保）。
    /// `resolution == .high` のときのみ長辺の最低値を保証する（利用者が明示的に選ぶ場合の例外）。
    public static func pageSize(
        page: PageEntity,
        placements: [PlacementEntity],
        resolution: ExportResolution = .standard
    ) -> LayoutSize {
        let aspect = page.aspect.ratio // w/h

        var requiredHeights: [Double] = []
        for placement in placements {
            let cropPxH = placement.cropRect.height * Double(placement.photo.pixelHeight)
            guard placement.destRect.height > 0 else { continue }
            // この写真を原寸で置くために必要なページ高さ
            requiredHeights.append(cropPxH / placement.destRect.height)
        }

        var heightPx = requiredHeights.max() ?? (
            aspect >= 1 ? fallbackShortEdge : fallbackShortEdge / aspect
        )
        var widthPx = heightPx * aspect

        let longEdge = max(widthPx, heightPx)
        if longEdge > maxLongEdge {
            let scale = maxLongEdge / longEdge
            widthPx *= scale
            heightPx *= scale
        } else if resolution.minLongEdge > 0, longEdge < resolution.minLongEdge {
            let scale = resolution.minLongEdge / longEdge
            widthPx *= scale
            heightPx *= scale
        }

        // 偶数pxに丸める（動画変換や一部デコーダとの相性・JPEGサブサンプリング対策）
        return LayoutSize(
            width: Double(Int(widthPx.rounded()) & ~1),
            height: Double(Int(heightPx.rounded()) & ~1)
        )
    }
}
