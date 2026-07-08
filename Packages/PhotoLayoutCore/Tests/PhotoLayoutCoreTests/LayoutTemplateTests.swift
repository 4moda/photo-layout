import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("レイアウトテンプレート")
struct LayoutTemplateTests {
    @Test("枚数別テンプレートのスロット数が写真枚数と一致する", arguments: [1, 2, 3, 4])
    func slotCountsMatchPhotoCount(count: Int) {
        for template in LayoutTemplateTable.templates(forPhotoCount: count) {
            #expect(template.slotCount == count)
            for slot in template.slots {
                #expect(LayoutRect.unit.contains(slot))
            }
        }
    }

    @Test("2枚左右分割はスロットが重ならない")
    func twoUpSlotsDontOverlap() {
        let template = LayoutTemplateTable.twoUp()[0]
        let overlap = template.slots[0].intersection(template.slots[1])
        #expect(overlap.width <= 0 || overlap.height <= 0)
    }

    @Test("Xタイムラインテンプレートは推奨アスペクトを持つ")
    func xTemplateHasRecommendedAspect() {
        let template = LayoutTemplateTable.xTimeline(photoCount: 3)
        #expect(template.slotCount == 3)
        #expect(template.recommendedAspect == AspectRatio(width: 16, height: 9))
    }
}

@Suite("テンプレート適用")
struct ApplyTemplateTests {
    private func makeProject(photoCount: Int, pageAspect: AspectRatio) -> ProjectEntity {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: pageAspect)])
        let photo = PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 3000)
        project.placements = (0..<photoCount).map { i in
            PlacementEntity(sortIndex: i, pageIndex: 0, photo: photo, destRect: .unit)
        }
        return project
    }

    private func destPixelAspect(_ p: PlacementEntity, page: PageEntity) -> Double {
        p.destRect.aspectRatio * page.contentAspect
    }

    private func cropPixelAspect(_ p: PlacementEntity) -> Double {
        (p.cropRect.width * Double(p.photo.pixelWidth)) / (p.cropRect.height * Double(p.photo.pixelHeight))
    }

    @Test("各placementがスロット矩形へ配置され、不変条件（dest==cropのpxアスペクト）が保たれる")
    func placementsFillSlotsPreservingInvariant() {
        var project = makeProject(photoCount: 3, pageAspect: AspectRatio(width: 16, height: 9))
        let template = LayoutTemplateTable.threeUp()[0]
        project.applyTemplate(template, toPage: 0)
        let page = project.page(at: 0)!
        for (offset, placement) in project.placements(onPage: 0).enumerated() {
            #expect(placement.destRect.isApproximatelyEqual(to: template.slots[offset]))
            #expect(abs(destPixelAspect(placement, page: page) - cropPixelAspect(placement)) < 1e-9)
            #expect(LayoutRect.unit.contains(placement.cropRect))
        }
    }

    @Test("写真がスロットより少ない場合は余ったスロットを使わず既存分だけ配置")
    func fewerPhotosThanSlots() {
        var project = makeProject(photoCount: 1, pageAspect: AspectRatio(width: 16, height: 9))
        let template = LayoutTemplateTable.fourUp()[0] // 4スロット
        project.applyTemplate(template, toPage: 0)
        #expect(project.placements(onPage: 0).count == 1)
        #expect(project.placements(onPage: 0)[0].destRect.isApproximatelyEqual(to: template.slots[0]))
    }
}
