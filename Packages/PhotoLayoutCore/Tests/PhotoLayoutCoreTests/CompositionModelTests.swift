import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("構図モデル（SlotSpec / SlotAssignment）")
struct CompositionModelTests {
    @Test("SlotSpec: Codableラウンドトリップ（クリップ形状・窓ごとの縁を保持）")
    func slotSpecRoundTrip() throws {
        let spec = SlotSpec(
            rect: LayoutRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            clipShape: .rectangle,
            frameStyle: PhotoFrameStyle(borderColor: .white, borderWidthRatio: 0.01, cornerRadiusRatio: 0.02)
        )
        let data = try JSONEncoder().encode([spec])
        let decoded = try JSONDecoder().decode([SlotSpec].self, from: data)
        #expect(decoded == [spec])
    }

    @Test("SlotSpec: 近似比較はrectの誤差を許容し、形状・縁の違いは区別する")
    func slotSpecApproximateEquality() {
        let base = SlotSpec(rect: LayoutRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let nudged = SlotSpec(rect: LayoutRect(x: 1e-9, y: 0, width: 0.5, height: 0.5))
        #expect(base.isApproximatelyEqual(to: nudged))

        let framed = SlotSpec(
            rect: base.rect,
            frameStyle: PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.01, cornerRadiusRatio: 0)
        )
        #expect(!base.isApproximatelyEqual(to: framed))
    }

    @Test("SlotAssignment: slotIndex互換アクセサは.pageSlotと相互変換される")
    func slotAssignmentCompatibilityAccessor() {
        var placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "p.jpg", pixelWidth: 100, pixelHeight: 100),
            destRect: .unit
        )
        #expect(placement.slot == nil)
        #expect(placement.slotIndex == nil)

        placement.slotIndex = 2
        #expect(placement.slot == .pageSlot(index: 2))
        #expect(placement.slotIndex == 2)

        placement.slotIndex = nil
        #expect(placement.slot == nil)
    }

    @Test("applyTemplate→assignPhotoの流れでスロット拘束が.pageSlotとして表現される")
    func templateFlowUsesPageSlotAssignment() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.applyTemplate(LayoutTemplateTable.twoUp()[0], toPage: 0)
        project.assignPhoto(
            PhotoRef(fileName: "a.jpg", pixelWidth: 2000, pixelHeight: 1000), toPage: 0, slot: 1)
        let placement = project.placements(onPage: 0)[0]
        #expect(placement.slot == .pageSlot(index: 1))
        #expect(project.emptySlotIndices(onPage: 0) == [0])
    }
}
