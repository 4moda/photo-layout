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
