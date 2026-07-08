import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("はみ出し配置の可視部分描画")
struct OverflowRenderTests {
    private func makeProject(destRect: LayoutRect) -> (PageEntity, PlacementEntity) {
        let page = PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 4000),
            cropRect: .unit,
            destRect: destRect
        )
        return (page, placement)
    }

    @Test("右へ20%はみ出した全面写真: 見える80%だけが描かれ、sourceも左80%に切られる")
    func overflowRightDrawsVisiblePart() {
        let (page, placement) = makeProject(destRect: LayoutRect(x: 0.2, y: 0, width: 1, height: 1))
        let plan = RenderPlanBuilder.build(
            page: page, placements: [placement], defaultFrame: .none,
            pagePixelSize: LayoutSize(width: 1000, height: 1000)
        )
        guard case .drawImage(_, _, let source, let dest, _)? = plan.dropFirst().first else {
            Issue.record("drawImageコマンドがない")
            return
        }
        // 描画先はページ内の見える部分（x: 200..1000）
        #expect(dest.isApproximatelyEqual(to: LayoutRect(x: 200, y: 0, width: 800, height: 1000), tolerance: 1e-6))
        // sourceは元画像の左80%
        #expect(source.isApproximatelyEqual(to: LayoutRect(x: 0, y: 0, width: 0.8, height: 1), tolerance: 1e-9))
    }

    @Test("拡大（destRect>領域）: 中央の見える部分がsourceの中央に対応する")
    func enlargedFullBleedActsAsCropZoom() {
        let (page, placement) = makeProject(destRect: LayoutRect(x: -0.25, y: -0.25, width: 1.5, height: 1.5))
        let plan = RenderPlanBuilder.build(
            page: page, placements: [placement], defaultFrame: .none,
            pagePixelSize: LayoutSize(width: 900, height: 900)
        )
        guard case .drawImage(_, _, let source, let dest, _)? = plan.dropFirst().first else {
            Issue.record("drawImageコマンドがない")
            return
        }
        #expect(dest.isApproximatelyEqual(to: LayoutRect(x: 0, y: 0, width: 900, height: 900), tolerance: 1e-6))
        // 1.5倍に拡大 → 見えるのは中央 2/3
        let third = 0.25 / 1.5
        #expect(source.isApproximatelyEqual(
            to: LayoutRect(x: third, y: third, width: 1 / 1.5, height: 1 / 1.5), tolerance: 1e-9
        ))
    }

    @Test("完全に領域外の配置は描画コマンドを出さない")
    func fullyOutsideIsSkipped() {
        let (page, placement) = makeProject(destRect: LayoutRect(x: 2, y: 0, width: 1, height: 1))
        let plan = RenderPlanBuilder.build(
            page: page, placements: [placement], defaultFrame: .none,
            pagePixelSize: LayoutSize(width: 1000, height: 1000)
        )
        #expect(plan.count == 1) // 背景fillのみ
    }
}

@Suite("Xタイムライン合成レイアウト")
struct XTimelineCompositeTests {
    @Test("枚数ごとのスロット数とキャンバスアスペクト", arguments: [1, 2, 3, 4])
    func slotCounts(count: Int) {
        let slots = XTimelineComposite.slots(photoCount: count)
        #expect(slots.count == count)
        let aspect = XTimelineComposite.canvasAspect(photoCount: count)
        if count == 1 {
            #expect(aspect == PlatformSpecTable.xPageAspects(photoCount: 1)[0])
        } else {
            #expect(aspect == AspectRatio(width: 16, height: 9))
        }
        // すべてのスロットはキャンバス内に収まり、互いに重ならない
        for slot in slots {
            #expect(LayoutRect.unit.contains(slot))
        }
        for (i, a) in slots.enumerated() {
            for b in slots.dropFirst(i + 1) {
                let overlap = a.intersection(b)
                #expect(overlap.width <= 0 || overlap.height <= 0)
            }
        }
    }

    @Test("スロットのpxアスペクトはPlatformSpecTableのページアスペクトに近い")
    func slotAspectsMatchPageAspects() {
        for count in 1...4 {
            let canvas = XTimelineComposite.canvasAspect(photoCount: count)
            let slots = XTimelineComposite.slots(photoCount: count)
            let pageAspects = PlatformSpecTable.xPageAspects(photoCount: count)
            for (slot, pageAspect) in zip(slots, pageAspects) {
                // 名目キャンバス（w=ratio, h=1）上のスロット実寸アスペクト
                let slotPixelAspect = (slot.width * canvas.ratio) / slot.height
                // ギャップの分だけ厳密には一致しない。3%以内なら許容
                #expect(abs(slotPixelAspect - pageAspect.ratio) / pageAspect.ratio < 0.03)
            }
        }
    }

    @Test("3枚: 左1列＋右2段の構成")
    func threePhotoArrangement() {
        let slots = XTimelineComposite.slots(photoCount: 3)
        #expect(slots[0].height == 1)               // 左は全高
        #expect(slots[1].minY < slots[2].minY)      // 右は上下
        #expect(abs(slots[1].minX - slots[2].minX) < 1e-12)
        #expect(slots[0].maxX < slots[1].minX)      // 左右は隙間で分離
    }
}

@Suite("ページ追加・削除")
struct PageMutationTests {
    private func makeProject() -> ProjectEntity {
        var project = ProjectEntity(
            title: "t",
            pages: [
                PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5)),
                PageEntity(index: 1, aspect: AspectRatio(width: 4, height: 5))
            ]
        )
        project.placements = [
            PlacementEntity(
                sortIndex: 0, pageIndex: 0,
                photo: PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100),
                destRect: .unit
            ),
            PlacementEntity(
                sortIndex: 1, pageIndex: 1,
                photo: PhotoRef(fileName: "b.jpg", pixelWidth: 100, pixelHeight: 100),
                destRect: .unit
            )
        ]
        return project
    }

    @Test("appendPage: 最後のページのアスペクト・背景を引き継いで末尾に追加")
    func appendInheritsLastPage() {
        var project = makeProject()
        project.appendPage()
        #expect(project.pages.count == 3)
        #expect(project.page(at: 2)?.aspect == AspectRatio(width: 4, height: 5))
        #expect(project.orderedPages.map(\.index) == [0, 1, 2])
    }

    @Test("removePage: ページと配置が消え、後続indexが詰まる")
    func removeShiftsIndices() {
        var project = makeProject()
        project.removePage(at: 0)
        #expect(project.pages.count == 1)
        #expect(project.pages[0].index == 0)
        #expect(project.placements.count == 1)
        #expect(project.placements[0].pageIndex == 0)
        #expect(project.placements[0].photo.fileName == "b.jpg")
    }

    @Test("removePage: 最後の1ページは削除できない")
    func cannotRemoveLastPage() {
        var project = makeProject()
        project.removePage(at: 0)
        project.removePage(at: 0)
        #expect(project.pages.count == 1)
    }
}
