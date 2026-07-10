import Foundation
import Testing
@testable import PhotoLayoutCore

/// スロット先行テンプレート（型枠→空スロット→当てはめ）とカルーセル分割のテスト。
@Suite("スロット先行テンプレート")
struct SlotTemplateTests {
    private let photo = PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 3000)

    private func cropPixelAspect(_ p: PlacementEntity) -> Double {
        (p.cropRect.width * Double(p.photo.pixelWidth)) / (p.cropRect.height * Double(p.photo.pixelHeight))
    }

    @Test("空ページにテンプレを敷くとスロットが保持され全スロットが空")
    func applyTemplateToEmptyPageCreatesEmptySlots() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let template = LayoutTemplateTable.fourUp()[0] // 4スロット
        project.applyTemplate(template, toPage: 0)
        #expect(project.page(at: 0)?.slots?.count == 4)
        #expect(project.emptySlotIndices(onPage: 0) == [0, 1, 2, 3])
        #expect(project.placements(onPage: 0).isEmpty)
    }

    @Test("空スロットに写真を当てはめると充填され、不変条件が保たれる")
    func assignPhotoFillsSlotPreservingInvariant() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let template = LayoutTemplateTable.twoUp()[0] // 左右2分割
        project.applyTemplate(template, toPage: 0)

        project.assignPhoto(photo, toPage: 0, slot: 1)
        #expect(project.emptySlotIndices(onPage: 0) == [0])

        let placed = project.placements(onPage: 0)
        #expect(placed.count == 1)
        let p = placed[0]
        #expect(p.slotIndex == 1)
        #expect(p.destRect.isApproximatelyEqual(to: template.slots[1]))
        let page = project.page(at: 0)!
        let slotPxAspect = template.slots[1].aspectRatio * page.contentAspect
        #expect(abs(cropPixelAspect(p) - slotPxAspect) < 1e-9)
        #expect(LayoutRect.unit.contains(p.cropRect))
    }

    @Test("同じスロットへの当てはめは置き換えになる")
    func assignReplacesSameSlot() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.applyTemplate(LayoutTemplateTable.twoUp()[0], toPage: 0)
        let other = PhotoRef(fileName: "b.jpg", pixelWidth: 3000, pixelHeight: 4000)
        project.assignPhoto(photo, toPage: 0, slot: 0)
        project.assignPhoto(other, toPage: 0, slot: 0)
        let placed = project.placements(onPage: 0)
        #expect(placed.count == 1)
        #expect(placed[0].photo.fileName == "b.jpg")
        #expect(project.emptySlotIndices(onPage: 0) == [1])
    }

    @Test("スロット数を超える写真はテンプレ適用で外れる")
    func extraPhotosDroppedOnApply() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.placements = (0..<3).map { PlacementEntity(sortIndex: $0, pageIndex: 0, photo: photo, destRect: .unit) }
        project.applyTemplate(LayoutTemplateTable.twoUp()[0], toPage: 0) // 2スロット
        let placed = project.placements(onPage: 0)
        #expect(placed.count == 2)
        #expect(Set(placed.compactMap(\.slotIndex)) == [0, 1])
        #expect(project.emptySlotIndices(onPage: 0).isEmpty)
    }
}

@Suite("カルーセル分割")
struct SplitPhotoTests {
    private let photo = PhotoRef(fileName: "pano.jpg", pixelWidth: 6000, pixelHeight: 2000)

    private func cropPixelAspect(_ p: PlacementEntity) -> Double {
        (p.cropRect.width * Double(p.photo.pixelWidth)) / (p.cropRect.height * Double(p.photo.pixelHeight))
    }

    @Test("N分割でNページ生成・各スライドが指定アスペクト・単一スロット")
    func splitCreatesNSlides() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let slide = AspectRatio(width: 4, height: 5)
        project.splitPhoto(photo, intoSlides: 3, slideAspect: slide)
        #expect(project.pages.count == 3)
        for page in project.orderedPages {
            #expect(page.aspect == slide)
            #expect(page.slots?.count == 1)
        }
        #expect(project.placements.count == 3)
    }

    @Test("各スライスは元画像を隙間なくタイル状に分割し、不変条件を保つ")
    func slicesTileSourceContiguously() {
        var project = ProjectEntity()
        let slide = AspectRatio(width: 4, height: 5)
        project.splitPhoto(photo, intoSlides: 3, slideAspect: slide)
        let slides = project.orderedPages
        let slideContentAspect = slides[0].contentAspect

        var placements = [PlacementEntity]()
        for page in slides {
            let onPage = project.placements(onPage: page.index)
            #expect(onPage.count == 1)
            placements.append(onPage[0])
        }
        // 各スライスのピクセルアスペクト ≒ スライドの配置領域アスペクト（歪まない）
        for p in placements {
            #expect(p.destRect.isApproximatelyEqual(to: .unit))
            #expect(abs(cropPixelAspect(p) - slideContentAspect) < 1e-9)
        }
        // 隣り合うスライスは連続（前のmaxX == 次のminX）、全体で元画像のフィル領域を覆う
        for i in 0..<(placements.count - 1) {
            #expect(abs(placements[i].cropRect.maxX - placements[i + 1].cropRect.minX) < 1e-9)
            #expect(abs(placements[i].cropRect.y - placements[i + 1].cropRect.y) < 1e-9)
            #expect(abs(placements[i].cropRect.height - placements[i + 1].cropRect.height) < 1e-9)
        }
    }

    @Test("分割枚数は1..20にクランプ")
    func splitClampsCount() {
        var project = ProjectEntity()
        project.splitPhoto(photo, intoSlides: 99, slideAspect: AspectRatio(width: 1, height: 1))
        #expect(project.pages.count == 20)
        project.splitPhoto(photo, intoSlides: 0, slideAspect: AspectRatio(width: 1, height: 1))
        #expect(project.pages.count == 1)
    }
}

@Suite("ページ操作（複製・スタイル）")
struct PageOpsTests {
    private let photo = PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 3000)

    @Test("スライド複製: 直後に挿入され、写真もコピーされ、後続indexがずれる")
    func duplicatePageInsertsCopy() {
        var project = ProjectEntity(pages: [
            PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1)),
            PageEntity(index: 1, aspect: AspectRatio(width: 1, height: 1))
        ])
        project.placements = [
            PlacementEntity(sortIndex: 0, pageIndex: 0, photo: photo, destRect: .unit),
            PlacementEntity(sortIndex: 1, pageIndex: 1, photo: photo, destRect: .unit)
        ]
        project.duplicatePage(at: 0)
        #expect(project.pages.count == 3)
        // 元ページ0の写真1枚 → 複製で新ページ1にも1枚
        #expect(project.placements(onPage: 0).count == 1)
        #expect(project.placements(onPage: 1).count == 1)
        // 元の2ページ目は index 2 へ押し出される
        #expect(project.placements(onPage: 2).count == 1)
        // 複製された配置は別idを持つ
        let ids = project.placements.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("ページ別スタイル: そのページの背景と枠だけ変わる")
    func setPageStyleAffectsOnlyThatPage() {
        var project = ProjectEntity(pages: [
            PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1)),
            PageEntity(index: 1, aspect: AspectRatio(width: 1, height: 1))
        ])
        project.placements = [PlacementEntity(sortIndex: 0, pageIndex: 0, photo: photo, destRect: .unit)]
        project.setPageStyle(.blackBackgroundWhiteBorder, pageIndex: 0)
        #expect(project.page(at: 0)?.background == FramePreset.blackBackgroundWhiteBorder.background)
        #expect(project.page(at: 1)?.background != FramePreset.blackBackgroundWhiteBorder.background)
        #expect(project.placements(onPage: 0)[0].frameOverride == FramePreset.blackBackgroundWhiteBorder.photoFrame)
    }
}
