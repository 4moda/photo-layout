import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("配置ロック: PlacementEntity.allowsGeometryGesture")
struct PlacementLockGestureGuardTests {
    private func makePlacement(isLocked: Bool) -> PlacementEntity {
        PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100),
            destRect: .unit,
            isLocked: isLocked
        )
    }

    @Test("ロック中はジオメトリ操作を許可しない")
    func lockedDisallowsGesture() {
        #expect(makePlacement(isLocked: true).allowsGeometryGesture == false)
    }

    @Test("未ロックはジオメトリ操作を許可する")
    func unlockedAllowsGesture() {
        #expect(makePlacement(isLocked: false).allowsGeometryGesture == true)
    }

    @Test("既定値は未ロック")
    func defaultsToUnlocked() {
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100),
            destRect: .unit
        )
        #expect(placement.isLocked == false)
        #expect(placement.allowsGeometryGesture == true)
    }
}

@Suite("配置ロック: setPlacementLocked")
struct SetPlacementLockedTests {
    private func makeProject() -> ProjectEntity {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.placements = [PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100),
            destRect: .unit
        )]
        return project
    }

    @Test("trueでロック、falseで解除できる")
    func togglesLockState() {
        var project = makeProject()
        let id = project.placements[0].id
        project.setPlacementLocked(true, placementID: id)
        #expect(project.placements[0].isLocked == true)
        project.setPlacementLocked(false, placementID: id)
        #expect(project.placements[0].isLocked == false)
    }

    @Test("存在しないIDは何もしない")
    func unknownIDIsNoop() {
        var project = makeProject()
        project.setPlacementLocked(true, placementID: UUID())
        #expect(project.placements[0].isLocked == false)
    }
}

@Suite("配置ロック: removePlacementのロックガード")
struct RemovePlacementLockGuardTests {
    private func makeProject(isLocked: Bool) -> (ProjectEntity, UUID) {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100),
            destRect: .unit,
            isLocked: isLocked
        )
        project.placements = [placement]
        return (project, placement.id)
    }

    @Test("ロック中の写真は削除されない")
    func lockedPlacementIsNotRemoved() {
        var (project, id) = makeProject(isLocked: true)
        project.removePlacement(id: id)
        #expect(project.placements.count == 1)
        #expect(project.placements[0].id == id)
    }

    @Test("未ロックの写真は削除される")
    func unlockedPlacementIsRemoved() {
        var (project, id) = makeProject(isLocked: false)
        project.removePlacement(id: id)
        #expect(project.placements.isEmpty)
    }

    @Test("解除後は削除できる")
    func removableAfterUnlock() {
        var (project, id) = makeProject(isLocked: true)
        project.setPlacementLocked(false, placementID: id)
        project.removePlacement(id: id)
        #expect(project.placements.isEmpty)
    }
}

@Suite("配置ロック: ロック中も許可される操作")
struct AllowedWhileLockedTests {
    private func makeProject() -> (ProjectEntity, UUID) {
        var project = ProjectEntity(pages: [
            PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))
        ])
        let photo = PhotoRef(fileName: "a.jpg", pixelWidth: 100, pixelHeight: 100)
        project.placements = [
            PlacementEntity(sortIndex: 0, pageIndex: 0, photo: photo, destRect: .unit, isLocked: true),
            PlacementEntity(sortIndex: 1, pageIndex: 0, photo: photo, destRect: .unit)
        ]
        return (project, project.placements[0].id)
    }

    @Test("ロック中でも重なり順変更（bringForward）は行える")
    func bringForwardAllowedWhileLocked() {
        var (project, lockedID) = makeProject()
        project.bringForward(placementID: lockedID)
        #expect(project.placements(onPage: 0).last?.id == lockedID)
        #expect(project.placements.first { $0.id == lockedID }?.isLocked == true)
    }

    @Test("ロック中でも枠スタイル変更（setPlacementFrame）は行える")
    func setPlacementFrameAllowedWhileLocked() {
        var (project, lockedID) = makeProject()
        let frame = PhotoFrameStyle(borderColor: .white, borderWidthRatio: 0.02, cornerRadiusRatio: 0)
        project.setPlacementFrame(frame, placementID: lockedID)
        #expect(project.placements.first { $0.id == lockedID }?.frameOverride == frame)
        #expect(project.placements.first { $0.id == lockedID }?.isLocked == true)
    }
}
