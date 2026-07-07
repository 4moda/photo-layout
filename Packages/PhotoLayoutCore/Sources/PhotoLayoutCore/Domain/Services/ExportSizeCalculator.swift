import Foundation

/// 書き出しピクセルサイズの決定。
/// 「元画像の実解像度を活かし、かつXの再圧縮を避ける長辺4096px以内」が原則。
public enum ExportSizeCalculator {
    public static let maxLongEdge: Double = 4096
    /// 写真が1枚もない等の場合の既定出力（短辺基準）
    public static let fallbackShortEdge: Double = 2048

    /// ページの出力ピクセルサイズを決める。
    /// 各placementのクロップ後実解像度がdestRect比率で必要とするページサイズの最大値を採用し、
    /// 長辺4096pxにクランプする（アップスケールはしない方針だが、最低でもfallbackは確保）。
    public static func pageSize(page: PageEntity, placements: [PlacementEntity]) -> LayoutSize {
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
        }

        // 偶数pxに丸める（動画変換や一部デコーダとの相性・JPEGサブサンプリング対策）
        return LayoutSize(
            width: Double(Int(widthPx.rounded()) & ~1),
            height: Double(Int(heightPx.rounded()) & ~1)
        )
    }
}
