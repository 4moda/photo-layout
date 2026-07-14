import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("プロジェクト複製（DuplicateProjectUseCase）")
struct DuplicateProjectTests {
    private func makeProject() -> ProjectEntity {
        var project = ProjectEntity(
            title: "元",
            pages: [
                PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1)),
                PageEntity(index: 1, aspect: AspectRatio(width: 1, height: 1))
            ]
        )
        project.addPhoto(PhotoRef(fileName: "a.jpg", pixelWidth: 3000, pixelHeight: 2000), toPage: 0)
        project.addPhoto(PhotoRef(fileName: "b.jpg", pixelWidth: 2000, pixelHeight: 3000), toPage: 1)
        return project
    }

    @Test("プロジェクト/ページ/配置すべて新IDで、内容とファイル参照は同じ")
    func duplicatedHasFreshIDs() async throws {
        let source = makeProject()
        let repo = InMemoryProjectRepository()
        let copy = try await DuplicateProjectUseCase(repository: repo).execute(source)

        #expect(copy.id != source.id)
        #expect(Set(copy.pages.map(\.id)).isDisjoint(with: source.pages.map(\.id)))
        #expect(Set(copy.placements.map(\.id)).isDisjoint(with: source.placements.map(\.id)))

        // 内容（構図）は同一: ページ数・配置のジオメトリ・写真ファイル参照
        #expect(copy.pages.count == source.pages.count)
        #expect(copy.placements.count == source.placements.count)
        #expect(copy.orderedPlacements.map(\.destRect) == source.orderedPlacements.map(\.destRect))
        #expect(copy.orderedPlacements.map(\.photo.fileName) == source.orderedPlacements.map(\.photo.fileName))

        // 保存されている
        let saved = try await repo.fetch(id: copy.id)
        #expect(saved?.id == copy.id)
    }

    @Test("複製元は変更されない（IDも内容もそのまま）")
    func sourceUntouched() async throws {
        let source = makeProject()
        let before = source
        _ = try await DuplicateProjectUseCase(repository: InMemoryProjectRepository()).execute(source)
        #expect(source == before)
    }
}

@Suite("写真差し替え（ReplacePhotoUseCase / ProjectEntity.replacePhoto）")
struct ReplacePhotoTests {
    private func makeProject() -> ProjectEntity {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.addPhoto(PhotoRef(fileName: "old.jpg", pixelWidth: 3000, pixelHeight: 2000), toPage: 0)
        return project
    }

    @Test("destRect・sortIndexは維持され、写真とクロップだけが変わる")
    func replaceKeepsGeometry() async throws {
        let project = makeProject()
        let placement = project.placements[0]
        let repo = InMemoryProjectRepository()
        try await repo.save(project)

        let updated = try await ReplacePhotoUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(project: project, placementID: placement.id, imageData: Data(count: 42))

        let replaced = updated.placements[0]
        #expect(replaced.id == placement.id)
        #expect(replaced.destRect == placement.destRect)
        #expect(replaced.sortIndex == placement.sortIndex)
        #expect(replaced.photo.fileName != placement.photo.fileName)
        #expect(replaced.cropRotation == 0)

        // 不変条件: cropRectのピクセルアスペクト == destRectのピクセルアスペクト（枠は歪まない）
        guard let page = updated.page(at: replaced.pageIndex) else {
            Issue.record("page not found")
            return
        }
        let frameAspect = replaced.destRect.aspectRatio * page.contentAspect
        let cropPxAspect = (replaced.cropRect.width * Double(replaced.photo.pixelWidth))
            / (replaced.cropRect.height * Double(replaced.photo.pixelHeight))
        #expect(abs(cropPxAspect - frameAspect) < 1e-9)
    }

    @Test("ロック中の写真は差し替えられない（保存もされない）")
    func lockedPlacementIsNotReplaced() async throws {
        var project = makeProject()
        let placementID = project.placements[0].id
        project.placements[0].isLocked = true
        let repo = InMemoryProjectRepository()
        try await repo.save(project)
        let updatedAtBefore = project.updatedAt

        let result = try await ReplacePhotoUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(project: project, placementID: placementID, imageData: Data(count: 42))

        #expect(result.placements[0].photo.fileName == "old.jpg")
        #expect(result.updatedAt == updatedAtBefore)
    }

    @Test("存在しないplacementIDでは何も変わらない")
    func unknownPlacementIsNoOp() async throws {
        let project = makeProject()
        let result = try await ReplacePhotoUseCase(
            photoStore: FakePhotoStore(), repository: InMemoryProjectRepository()
        ).execute(project: project, placementID: UUID(), imageData: Data(count: 1))
        #expect(result == project)
    }
}
