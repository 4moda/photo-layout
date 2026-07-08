/// ジェスチャ→ジオメトリ変更の純粋計算。
/// 操作体系（SCRL/Canva型・ユーザー確定仕様）:
/// - ドラッグ: destRect（枠）を移動。スナップあり
/// - ピンチ/角ドラッグ: destRectを中心固定・**アスペクト固定**で拡縮
/// - ダブルタップ後（クロップモード）: 枠を固定したまま中身（cropRect）をパン/ズーム
/// いずれも不変条件「destRectのpxアスペクト==cropRectのpxアスペクト」を壊さない。
public enum PlacementGesture {
    // MARK: - 枠（destRect）の操作

    /// ドラッグ移動。translationは配置領域の正規化座標での移動量。
    public static func move(
        destRect: LayoutRect,
        translationX: Double,
        translationY: Double,
        others: [LayoutRect] = [],
        snapThreshold: Double = 0.02
    ) -> SnapEngine.Result {
        var rect = destRect
        rect.x += translationX
        rect.y += translationY
        let snapped = SnapEngine.snap(moving: rect, others: others, threshold: snapThreshold)
        return SnapEngine.Result(
            rect: clampInsideUnit(snapped.rect),
            guides: snapped.guides
        )
    }

    /// 中心固定・アスペクト固定の拡縮。
    public static func scale(
        destRect: LayoutRect,
        factor: Double,
        minWidth: Double = 0.05,
        maxWidth: Double = 1.0
    ) -> LayoutRect {
        let currentWidth = destRect.width
        let clampedFactor = min(max(factor, minWidth / currentWidth), maxWidth / currentWidth)
        return clampInsideUnit(destRect.scaled(by: clampedFactor))
    }

    // MARK: - 枠内クロップ（cropRect）の操作

    /// クロップモードのパン: 画像を枠内でずらす。
    /// translationは枠（destRect）に対する正規化移動量。画像は逆方向へ動いて見えるため符号反転。
    public static func panCrop(
        cropRect: LayoutRect,
        translationX: Double,
        translationY: Double
    ) -> LayoutRect {
        var rect = cropRect
        rect.x -= translationX * cropRect.width
        rect.y -= translationY * cropRect.height
        return clampCropInsideSource(rect)
    }

    /// クロップモードのズーム: cropRectを中心固定で拡縮（幅・高さ同率なのでpxアスペクト不変）。
    /// factor > 1 でズームイン（cropRectは縮む）。
    public static func zoomCrop(
        cropRect: LayoutRect,
        factor: Double,
        minWidth: Double = 0.05
    ) -> LayoutRect {
        guard factor > 0 else { return cropRect }
        var scale = 1 / factor
        // 拡大しすぎ（cropRectが小さくなりすぎ）と、元画像からのはみ出しをクランプ
        scale = max(scale, minWidth / cropRect.width)
        scale = min(scale, 1 / max(cropRect.width, cropRect.height))
        return clampCropInsideSource(cropRect.scaled(by: scale))
    }

    // MARK: - クランプ

    /// 枠を配置領域(0..1)内に収める
    private static func clampInsideUnit(_ rect: LayoutRect) -> LayoutRect {
        var result = rect
        if result.width <= 1 {
            result.x = min(max(result.x, 0), 1 - result.width)
        } else {
            // 領域より大きい枠は中央寄せを許容（将来のはみ出し配置に備え両端を覆う範囲で）
            result.x = min(max(result.x, 1 - result.width), 0)
        }
        if result.height <= 1 {
            result.y = min(max(result.y, 0), 1 - result.height)
        } else {
            result.y = min(max(result.y, 1 - result.height), 0)
        }
        return result
    }

    /// クロップを元画像(0..1)内に収める
    private static func clampCropInsideSource(_ rect: LayoutRect) -> LayoutRect {
        var result = rect
        result.width = min(result.width, 1)
        result.height = min(result.height, 1)
        result.x = min(max(result.x, 0), 1 - result.width)
        result.y = min(max(result.y, 0), 1 - result.height)
        return result
    }
}
