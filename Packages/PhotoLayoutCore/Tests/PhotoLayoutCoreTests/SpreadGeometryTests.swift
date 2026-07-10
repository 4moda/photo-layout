import Testing
@testable import PhotoLayoutCore

@Suite("SpreadGeometry（隙間なしページ連結座標系）")
struct SpreadGeometryTests {
    private func project(aspects: [AspectRatio]) -> ProjectEntity {
        ProjectEntity(pages: aspects.enumerated().map { index, aspect in
            PageEntity(index: index, aspect: aspect)
        })
    }

    @Test("同一アスペクト（4:5×3）: 連結幅と各ページ原点")
    func uniformAspects() {
        let p = project(aspects: Array(repeating: AspectRatio(width: 4, height: 5), count: 3))
        let w = 0.8
        #expect(abs(SpreadGeometry.totalWidth(project: p) - w * 3) < 1e-12)
        #expect(SpreadGeometry.pageOriginX(project: p, pageIndex: 0) == 0)
        #expect(abs(SpreadGeometry.pageOriginX(project: p, pageIndex: 1)! - w) < 1e-12)
        #expect(abs(SpreadGeometry.pageOriginX(project: p, pageIndex: 2)! - w * 2) < 1e-12)
        #expect(SpreadGeometry.pageOriginX(project: p, pageIndex: 3) == nil)
        let frame1 = SpreadGeometry.pageFrame(project: p, pageIndex: 1)!
        #expect(frame1.isApproximatelyEqual(to: LayoutRect(x: w, y: 0, width: w, height: 1)))
    }

    @Test("異アスペクト混在（X 3枚: 8:9 + 16:9×2）も高さ1で隙間なく連結")
    func mixedAspects() {
        let aspects = PlatformSpecTable.xPageAspects(photoCount: 3)
        let p = project(aspects: aspects)
        let widths = aspects.map(\.ratio)
        #expect(abs(SpreadGeometry.totalWidth(project: p) - widths.reduce(0, +)) < 1e-12)
        // 隣接ページが正確に接する（隙間ゼロ）
        for index in 0..<2 {
            let left = SpreadGeometry.pageFrame(project: p, pageIndex: index)!
            let right = SpreadGeometry.pageFrame(project: p, pageIndex: index + 1)!
            #expect(abs(left.maxX - right.minX) < 1e-12)
        }
    }

    @Test("ページ⇄スプレッドの矩形変換は往復で一致する")
    func roundTripConversion() {
        let p = project(aspects: [
            AspectRatio(width: 8, height: 9),
            AspectRatio(width: 16, height: 9)
        ])
        let destRect = LayoutRect(x: 0.1, y: 0.25, width: 0.5, height: 0.4)
        let spread = SpreadGeometry.toSpread(pageRect: destRect, pageIndex: 1, project: p)!
        // ページ1の原点(8/9)から始まり、幅はページ幅(16/9)×0.5
        #expect(abs(spread.x - (8.0 / 9 + 0.1 * 16 / 9)) < 1e-12)
        #expect(abs(spread.width - 0.5 * 16 / 9) < 1e-12)
        #expect(abs(spread.y - 0.25) < 1e-12)

        let back = SpreadGeometry.toPage(spreadRect: spread, pageIndex: 1, project: p)!
        #expect(back.isApproximatelyEqual(to: destRect))
    }

    private func projectWithPhoto(destRect: LayoutRect, onPage pageIndex: Int) -> ProjectEntity {
        var p = project(aspects: [AspectRatio(width: 1, height: 1), AspectRatio(width: 1, height: 1)])
        p.placements = [PlacementEntity(
            sortIndex: 0, pageIndex: pageIndex,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 1000, pixelHeight: 1000),
            destRect: destRect
        )]
        return p
    }

    @Test("ページ内に収まる写真は所属ページだけに見え、隣には出ない")
    func containedPhotoOnlyOnItsPage() {
        let p = projectWithPhoto(destRect: LayoutRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4), onPage: 0)
        #expect(SpreadGeometry.visiblePlacements(onPage: 0, project: p).count == 1)
        #expect(SpreadGeometry.visiblePlacements(onPage: 1, project: p).isEmpty)
    }

    @Test("隣にはみ出した写真は両ページに現れ、隣ではローカル座標へ写像される")
    func overflowingPhotoAppearsOnBothPages() {
        // ページ0で x=0.6..1.4（右へはみ出す）
        let p = projectWithPhoto(destRect: LayoutRect(x: 0.6, y: 0.2, width: 0.8, height: 0.6), onPage: 0)
        let onP0 = SpreadGeometry.visiblePlacements(onPage: 0, project: p)
        let onP1 = SpreadGeometry.visiblePlacements(onPage: 1, project: p)
        #expect(onP0.count == 1)
        #expect(onP1.count == 1)
        // ページ1では x が 1ページ分（1.0）左へずれる: 0.6-1.0 = -0.4
        #expect(onP1[0].destRect.isApproximatelyEqual(
            to: LayoutRect(x: -0.4, y: 0.2, width: 0.8, height: 0.6)))
        #expect(onP0[0].destRect.isApproximatelyEqual(
            to: LayoutRect(x: 0.6, y: 0.2, width: 0.8, height: 0.6)))
    }

    @Test("完全に隣へ移動した写真は元ページから消え、隣ページにだけ現れる")
    func fullyMovedPhotoLeavesOriginPage() {
        // ページ0基準で x=1.1..1.6（完全にページ1側）
        let p = projectWithPhoto(destRect: LayoutRect(x: 1.1, y: 0.2, width: 0.5, height: 0.5), onPage: 0)
        #expect(SpreadGeometry.visiblePlacements(onPage: 0, project: p).isEmpty)
        let onP1 = SpreadGeometry.visiblePlacements(onPage: 1, project: p)
        #expect(onP1.count == 1)
        #expect(onP1[0].destRect.isApproximatelyEqual(
            to: LayoutRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)))
    }

    @Test("全スライド跨ぎ配置: destRect幅=ページ数・不変条件維持・全ページに現れる")
    func spanningAllSlides() {
        var p = project(aspects: Array(repeating: AspectRatio(width: 1, height: 1), count: 3))
        let photo = PhotoRef(fileName: "pano.jpg", pixelWidth: 3000, pixelHeight: 2000)
        p.placements = [PlacementEntity(sortIndex: 0, pageIndex: 0, photo: photo, destRect: .unit)]
        let id = p.placements[0].id
        p.placeSpanningAllSlides(placementID: id)

        let placed = p.placements[0]
        #expect(placed.destRect.isApproximatelyEqual(to: LayoutRect(x: 0, y: 0, width: 3, height: 1)))
        // 不変条件: destRectのpxアスペクト == cropRectのpxアスペクト（画像は歪まない）
        let destPx = placed.destRect.aspectRatio * p.page(at: 0)!.contentAspect
        let cropPx = (placed.cropRect.width * 3000) / (placed.cropRect.height * 2000)
        #expect(abs(destPx - cropPx) < 1e-9)
        // 3スライドそれぞれに見える
        for i in 0..<3 {
            #expect(SpreadGeometry.visiblePlacements(onPage: i, project: p).count == 1)
        }
    }

    @Test("スプレッドX→ページindex解決（境界は右側ページ）")
    func pageIndexAtX() {
        let p = project(aspects: [
            AspectRatio(width: 1, height: 1),
            AspectRatio(width: 1, height: 1)
        ])
        #expect(SpreadGeometry.pageIndex(atSpreadX: 0, project: p) == 0)
        #expect(SpreadGeometry.pageIndex(atSpreadX: 0.999, project: p) == 0)
        #expect(SpreadGeometry.pageIndex(atSpreadX: 1.0, project: p) == 1)
        #expect(SpreadGeometry.pageIndex(atSpreadX: 2.5, project: p) == nil)
        #expect(SpreadGeometry.pageIndex(atSpreadX: -0.1, project: p) == nil)
    }
}
