/// ページ内ジオメトリの共通計算。
/// RenderPlanBuilder（描画）とジェスチャ層（画面pt⇄正規化座標の変換）が同じ関数を使うことで、
/// 「触った場所」と「描かれる場所」のズレを構造的に防ぐ。
public enum PageGeometry {
    /// 余白を差し引いた配置領域。destRect正規化座標(0..1)の基準となる矩形。
    /// 余白は短辺基準の比率で保持されている（CLAUDE.md ルール4のpx化はここで行う）。
    public static func contentRect(page: PageEntity, pageSize: LayoutSize) -> LayoutRect {
        let ref = pageSize.referenceDimension
        let margins = page.background.margins
        return LayoutRect(
            x: margins.leading * ref,
            y: margins.top * ref,
            width: max(0, pageSize.width - (margins.leading + margins.trailing) * ref),
            height: max(0, pageSize.height - (margins.top + margins.bottom) * ref)
        )
    }

    /// destRect（配置領域の正規化座標）→ 実座標（px/pt）の矩形
    public static func imageRect(destRect: LayoutRect, in contentRect: LayoutRect) -> LayoutRect {
        LayoutRect(
            x: contentRect.x + destRect.x * contentRect.width,
            y: contentRect.y + destRect.y * contentRect.height,
            width: destRect.width * contentRect.width,
            height: destRect.height * contentRect.height
        )
    }
}
