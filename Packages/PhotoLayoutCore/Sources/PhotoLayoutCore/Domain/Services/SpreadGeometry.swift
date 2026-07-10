/// スプレッド空間: プロジェクトの全ページを高さ1.0で左から隙間なく横に並べた座標系。
/// シームレス連結キャンバス（Issue #9）とページまたぎ配置（フェーズ5）の基盤。
/// 各ページの幅は aspect.ratio。異アスペクト混在（X 3枚等）でも高さを揃えて連結できる。
/// 永続モデルは変えない（destRectはページ正規化＋pageIndexのまま）— スプレッドは表示・編集時の導出座標。
public enum SpreadGeometry {
    /// 指定ページの左端X（スプレッド空間）。存在しないindexにはnil
    public static func pageOriginX(project: ProjectEntity, pageIndex: Int) -> Double? {
        guard project.page(at: pageIndex) != nil else { return nil }
        return project.orderedPages
            .prefix { $0.index != pageIndex }
            .reduce(0) { $0 + $1.aspect.ratio }
    }

    /// 全ページを連結した幅（高さは常に1.0）
    public static func totalWidth(project: ProjectEntity) -> Double {
        project.orderedPages.reduce(0) { $0 + $1.aspect.ratio }
    }

    /// スプレッド空間内のページ矩形
    public static func pageFrame(project: ProjectEntity, pageIndex: Int) -> LayoutRect? {
        guard let originX = pageOriginX(project: project, pageIndex: pageIndex),
              let page = project.page(at: pageIndex) else { return nil }
        return LayoutRect(x: originX, y: 0, width: page.aspect.ratio, height: 1)
    }

    /// ページ正規化矩形（destRect等）→ スプレッド空間の矩形
    public static func toSpread(pageRect: LayoutRect, pageIndex: Int, project: ProjectEntity) -> LayoutRect? {
        guard let frame = pageFrame(project: project, pageIndex: pageIndex) else { return nil }
        return LayoutRect(
            x: frame.x + pageRect.x * frame.width,
            y: pageRect.y * frame.height,
            width: pageRect.width * frame.width,
            height: pageRect.height * frame.height
        )
    }

    /// スプレッド空間の矩形 → 指定ページの正規化矩形
    public static func toPage(spreadRect: LayoutRect, pageIndex: Int, project: ProjectEntity) -> LayoutRect? {
        guard let frame = pageFrame(project: project, pageIndex: pageIndex) else { return nil }
        return LayoutRect(
            x: (spreadRect.x - frame.x) / frame.width,
            y: spreadRect.y / frame.height,
            width: spreadRect.width / frame.width,
            height: spreadRect.height / frame.height
        )
    }

    /// 指定ページ上に「見える」配置一覧（隣ページからはみ出して重なるものも含む）。
    /// 各配置の destRect は対象ページのローカル正規化座標へ写像して返す（RenderPlanBuilder が
    /// 配置領域でクリップして見える部分だけ描く）。z順は sortIndex 準拠のまま。
    ///
    /// これにより「写真は1ページに所属」ではなく「プロジェクト（連結キャンバス）に配置」される概念になり、
    /// スライドをまたいだ写真が両スライドに写る（=拡大配置で手動シームレスカルーセルが作れる）。
    /// 余白ありページ間の写像は近似（余白ゼロのスライドで厳密）。所属ページ上では写像は恒等。
    public static func visiblePlacements(onPage pageIndex: Int, project: ProjectEntity) -> [PlacementEntity] {
        guard project.page(at: pageIndex) != nil else { return [] }
        var result: [PlacementEntity] = []
        for placement in project.orderedPlacements {
            guard let spread = toSpread(
                    pageRect: placement.destRect, pageIndex: placement.pageIndex, project: project),
                  let local = toPage(spreadRect: spread, pageIndex: pageIndex, project: project) else { continue }
            let inter = local.intersection(.unit)
            guard inter.width > 0, inter.height > 0 else { continue }
            var moved = placement
            moved.destRect = local
            result.append(moved)
        }
        return result
    }

    /// スプレッドX座標が属するページのindex（境界はその位置から始まるページ側）。範囲外はnil
    public static func pageIndex(atSpreadX x: Double, project: ProjectEntity) -> Int? {
        guard x >= 0 else { return nil }
        var cursor = 0.0
        for page in project.orderedPages {
            let next = cursor + page.aspect.ratio
            if x < next { return page.index }
            cursor = next
        }
        return nil
    }
}
