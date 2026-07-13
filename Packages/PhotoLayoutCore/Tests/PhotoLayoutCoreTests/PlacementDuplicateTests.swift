import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("配置複製: duplicatePlacement")
struct DuplicatePlacementTests {
    private let photo = PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100)

    private func makeProject() -> ProjectEntity {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.placements = [
            PlacementEntity(sortIndex: 0, pageIndex: 0, photo: photo, destRect: .unit),
            PlacementEntity(sortIndex: 1, pageIndex: 0, photo: photo, destRect: .unit)
        ]
        return project
    }

    @Test("複製後の配置は元のsortIndexの直後に挿入され、以降のsortIndexが1つずつ後ろへずれる")
    func insertsRightAfterSourceSortIndex() {
        var project = makeProject()
        let sourceID = project.placements[0].id
        let followingID = project.placements[1].id
        let newID = project.duplicatePlacement(placementID: sourceID)
        #expect(newID != nil)
        #expect(project.placements.first { $0.id == sourceID }?.sortIndex == 0)
        #expect(project.placements.first { $0.id == newID }?.sortIndex == 1)
        #expect(project.placements.first { $0.id == followingID }?.sortIndex == 2)
    }

    @Test("複製後の配置は別idを持ち、photo/cropRectは元と同一")
    func copiesPhotoAndCropRectWithNewID() {
        var project = makeProject()
        let sourceID = project.placements[0].id
        project.placements[0].cropRect = LayoutRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4)
        let source = project.placements[0]
        let newID = project.duplicatePlacement(placementID: sourceID)
        let copy = project.placements.first { $0.id == newID }
        #expect(newID != sourceID)
        #expect(copy?.photo == source.photo)
        #expect(copy?.cropRect == source.cropRect)
    }

    @Test("複製後のdestRectは元からオフセットしており完全には重ならない")
    func offsetsDestRectFromSource() {
        var project = makeProject()
        let sourceID = project.placements[0].id
        let source = project.placements[0]
        let newID = project.duplicatePlacement(placementID: sourceID)
        let copy = project.placements.first { $0.id == newID }
        #expect(copy?.destRect != source.destRect)
        #expect(copy?.destRect.width == source.destRect.width)
        #expect(copy?.destRect.height == source.destRect.height)
    }

    @Test("複製元がスロット拘束の場合、複製後はslotIndex=nilになり複製元のスロットは変わらない")
    func slottedSourceProducesFreeCopy() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.placements = [
            PlacementEntity(sortIndex: 0, pageIndex: 0, slotIndex: 2, photo: photo, destRect: .unit)
        ]
        let sourceID = project.placements[0].id
        let newID = project.duplicatePlacement(placementID: sourceID)
        #expect(project.placements.first { $0.id == sourceID }?.slotIndex == 2)
        #expect(project.placements.first { $0.id == newID }?.slotIndex == nil)
    }

    @Test("存在しないIDはnilを返し何も変更しない")
    func unknownIDIsNoop() {
        var project = makeProject()
        let before = project.placements
        let result = project.duplicatePlacement(placementID: UUID())
        #expect(result == nil)
        #expect(project.placements == before)
    }
}
