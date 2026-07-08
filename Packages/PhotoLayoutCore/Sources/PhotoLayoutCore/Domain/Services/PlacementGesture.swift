/// ジェスチャ→ジオメトリ変更の純粋計算。
/// 操作体系（SCRL/Canva型・ユーザー確定仕様）:
/// - ドラッグ: destRect（枠）を移動。スナップあり
/// - ピンチ/角ハンドル: destRectを中心固定・**アスペクト固定**で拡縮
/// - ダブルタップ後（クロップモード）: 枠を固定したまま中身（cropRect）をパン/ズーム。枠外タップで完了
/// 写真は配置領域からはみ出してよい（Canva同様）。見える部分だけ描くのはRenderPlanBuilderの責務。
/// いずれも不変条件「destRectのpxアスペクト==cropRectのpxアスペクト」を壊さない。
public enum PlacementGesture {
    /// 配置領域と重なり続けることを保証する最小の見え幅（正規化座標）
    public static let minVisible = 0.05

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
            rect: clampVisible(snapped.rect),
            guides: snapped.guides
        )
    }

    /// 中心固定・アスペクト固定の拡縮。全面配置からさらに拡大してクロップを詰めることもできる。
    public static func scale(
        destRect: LayoutRect,
        factor: Double,
        minWidth: Double = 0.05,
        maxWidth: Double = 4.0
    ) -> LayoutRect {
        let currentWidth = destRect.width
        let clampedFactor = min(max(factor, minWidth / currentWidth), maxWidth / currentWidth)
        return clampVisible(destRect.scaled(by: clampedFactor))
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

    /// はみ出しは許可しつつ、配置領域(0..1)と最低限の重なりは維持する
    /// （画面外へ飛んで触れなくなる事故を防ぐ）
    private static func clampVisible(_ rect: LayoutRect) -> LayoutRect {
        var result = rect
        result.x = min(max(result.x, minVisible - result.width), 1 - minVisible)
        result.y = min(max(result.y, minVisible - result.height), 1 - minVisible)
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
