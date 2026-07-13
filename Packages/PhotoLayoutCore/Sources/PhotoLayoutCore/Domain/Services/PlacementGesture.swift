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

    /// 矩形の角
    public enum Corner: Sendable {
        case topLeft, topRight, bottomLeft, bottomRight
        /// 対角（角ハンドルを掴んだとき固定される側）
        public var opposite: Corner {
            switch self {
            case .topLeft: return .bottomRight
            case .topRight: return .bottomLeft
            case .bottomLeft: return .topRight
            case .bottomRight: return .topLeft
            }
        }
    }

    /// 矩形の辺
    public enum Edge: Sendable {
        case top, bottom, leading, trailing
    }

    /// アンカー（固定する角）を不動点にしたアスペクト固定拡縮。
    /// 角ハンドルのドラッグでは「触っていない対角の頂点」をアンカーに渡す。
    public static func scaleAnchored(
        destRect: LayoutRect,
        factor: Double,
        anchor: Corner,
        minWidth: Double = 0.05,
        maxWidth: Double = 4.0
    ) -> LayoutRect {
        let clampedFactor = min(max(factor, minWidth / destRect.width), maxWidth / destRect.width)
        let width = destRect.width * clampedFactor
        let height = destRect.height * clampedFactor
        let rect: LayoutRect
        switch anchor {
        case .topLeft:
            rect = LayoutRect(x: destRect.minX, y: destRect.minY, width: width, height: height)
        case .topRight:
            rect = LayoutRect(x: destRect.maxX - width, y: destRect.minY, width: width, height: height)
        case .bottomLeft:
            rect = LayoutRect(x: destRect.minX, y: destRect.maxY - height, width: width, height: height)
        case .bottomRight:
            rect = LayoutRect(x: destRect.maxX - width, y: destRect.maxY - height, width: width, height: height)
        }
        return clampVisible(rect)
    }

    /// アスペクト固定拡縮に、ページ端（0/1）・中心（0.5）への吸着を加える。
    /// 動く角（アンカーの対角）が近ければ倍率を調整して端にピッタリ合わせ、ガイド線を返す。
    /// 移動時と同様の「スナップ」を拡大縮小にも提供する。
    public static func scaleAnchoredSnapped(
        destRect: LayoutRect,
        factor: Double,
        anchor: Corner,
        threshold: Double = 0.02
    ) -> (rect: LayoutRect, guides: [SnapEngine.Guide]) {
        let scaled = scaleAnchored(destRect: destRect, factor: factor, anchor: anchor)
        guard destRect.width > 0, destRect.height > 0 else { return (scaled, []) }
        // 固定される角（destRect基準）
        let anchorX: Double, anchorY: Double
        switch anchor {
        case .topLeft:     anchorX = destRect.minX; anchorY = destRect.minY
        case .topRight:    anchorX = destRect.maxX; anchorY = destRect.minY
        case .bottomLeft:  anchorX = destRect.minX; anchorY = destRect.maxY
        case .bottomRight: anchorX = destRect.maxX; anchorY = destRect.maxY
        }
        // 動く角（scaled基準）: アンカーが左端なら右端が動く、右端なら左端が動く
        let dragX = anchorX <= scaled.minX + 1e-9 ? scaled.maxX : scaled.minX
        let dragY = anchorY <= scaled.minY + 1e-9 ? scaled.maxY : scaled.minY
        let snapX = nearestCandidate(dragX, threshold: threshold)
        let snapY = nearestCandidate(dragY, threshold: threshold)
        // アスペクト固定なので片軸のみ吸着（距離が小さい方）
        if let sx = snapX, snapY == nil || sx.distance <= snapY!.distance {
            let f = abs(sx.candidate - anchorX) / destRect.width
            return (scaleAnchored(destRect: destRect, factor: f, anchor: anchor),
                    [SnapEngine.Guide(axis: .vertical, position: sx.candidate)])
        } else if let sy = snapY {
            let f = abs(sy.candidate - anchorY) / destRect.height
            return (scaleAnchored(destRect: destRect, factor: f, anchor: anchor),
                    [SnapEngine.Guide(axis: .horizontal, position: sy.candidate)])
        }
        return (scaled, [])
    }

    /// 値を {0, 0.5, 1} のうち最も近いものへ（しきい値以内なら）。
    private static func nearestCandidate(
        _ value: Double, threshold: Double
    ) -> (candidate: Double, distance: Double)? {
        var best: (candidate: Double, distance: Double)?
        for candidate in [0.0, 0.5, 1.0] {
            let distance = abs(candidate - value)
            if distance <= threshold, best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }
        return best
    }

    /// 辺ドラッグで枠を伸縮する（反対の辺は固定）。**枠のアスペクトが変わる**操作なので、
    /// 呼び出し側は ProjectEntity.resizeFrame(...) を通じてcropRectの再計算とセットで使うこと
    /// （画像は歪まず、枠の中で見せる範囲が変わるだけ）。
    /// - Parameter delta: 配置領域の正規化座標での移動量（leading/trailingはX、top/bottomはY）
    public static func stretchEdge(
        destRect: LayoutRect,
        edge: Edge,
        delta: Double,
        minSize: Double = 0.05
    ) -> LayoutRect {
        var rect = destRect
        switch edge {
        case .trailing:
            rect.width = max(destRect.width + delta, minSize)
        case .leading:
            let newWidth = max(destRect.width - delta, minSize)
            rect.x = destRect.maxX - newWidth
            rect.width = newWidth
        case .bottom:
            rect.height = max(destRect.height + delta, minSize)
        case .top:
            let newHeight = max(destRect.height - delta, minSize)
            rect.y = destRect.maxY - newHeight
            rect.height = newHeight
        }
        return clampVisible(rect)
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

    /// クロップモードの回転: 画面下の水平ドラッグバーの移動量から回転角度（度数法、時計回り）を計算する。
    /// translationXはバー全体に対する累積ドラッグ量（pt）で、バー幅いっぱいのドラッグで
    /// 最大角度の2倍（-maxDegrees〜+maxDegrees）動く。±maxDegreesにクランプし、傾け過ぎを防ぐ。
    public static func cropRotationFromDrag(
        baseDegrees: Double,
        translationX: Double,
        barWidth: Double,
        maxDegrees: Double = 45
    ) -> Double {
        guard barWidth > 0 else { return min(max(baseDegrees, -maxDegrees), maxDegrees) }
        let degrees = baseDegrees + (translationX / barWidth) * (maxDegrees * 2)
        return min(max(degrees, -maxDegrees), maxDegrees)
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
