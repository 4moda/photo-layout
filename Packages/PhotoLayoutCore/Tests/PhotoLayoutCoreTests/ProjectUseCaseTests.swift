import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("Project UseCases（フェイクRepository注入）")
struct ProjectUseCaseTests {
    @Test("X 3枚プリセットから非対称ページ構成が生成・保存される")
    func createXProject() async throws {
        let repo = InMemoryProjectRepository()
        let created = try await CreateProjectUseCase(repository: repo)
            .execute(title: "作例", preset: .x(photoCount: 3))

        let fetched = try await repo.fetch(id: created.id)
        #expect(fetched == created)
        let pages = created.orderedPages
        #expect(pages.count == 3)
        #expect(pages[0].aspect == AspectRatio(width: 8, height: 9))
        #expect(pages[1].aspect == AspectRatio(width: 16, height: 9))
        #expect(pages.map(\.index) == [0, 1, 2])
    }

    @Test("プリセットなしの既定はInstagram 4:5の1ページ")
    func createDefaultProject() async throws {
        let repo = InMemoryProjectRepository()
        let created = try await CreateProjectUseCase(repository: repo).execute()
        #expect(created.pages.count == 1)
        #expect(created.pages[0].aspect == AspectRatio(width: 4, height: 5))
        #expect(created.platformPreset == nil)
    }

    @Test("FramePresetが背景とデフォルトフレームに反映される")
    func createWithFramePreset() async throws {
        let repo = InMemoryProjectRepository()
        let created = try await CreateProjectUseCase(repository: repo)
            .execute(preset: .instagram(aspect: .square, pageCount: 1), framePreset: .whiteMarginBlackBorder)
        #expect(created.defaultPhotoFrame.borderColor == .black)
        #expect(created.pages[0].background.margins == EdgeInsetsRatio(uniform: 0.05))
    }

    @Test("一覧は更新日時の降順")
    func listSortedByUpdatedAt() async throws {
        let repo = InMemoryProjectRepository()
        let old = ProjectEntity(title: "old", updatedAt: Date(timeIntervalSince1970: 1000))
        let new = ProjectEntity(title: "new", updatedAt: Date(timeIntervalSince1970: 2000))
        try await repo.save(old)
        try await repo.save(new)

        let listed = try await ListProjectsUseCase(repository: repo).execute()
        #expect(listed.map(\.title) == ["new", "old"])
    }

    @Test("削除でRepositoryから消える")
    func deleteProject() async throws {
        let repo = InMemoryProjectRepository()
        let created = try await CreateProjectUseCase(repository: repo).execute()
        try await DeleteProjectUseCase(repository: repo).execute(id: created.id)
        #expect(try await repo.fetch(id: created.id) == nil)
        #expect(try await repo.fetchAll().isEmpty)
    }

    @Test("Entity往復: Codableエンコード→デコードで一致（永続化マッピングの前提）")
    func entityCodableRoundTrip() async throws {
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 6000),
            cropRect: LayoutRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
            contentMode: .fit,
            destRect: LayoutRect(x: 0.5, y: 0, width: 1.5, height: 1),
            frameOverride: FramePreset.blackBackgroundWhiteBorder.photoFrame
        )
        let project = ProjectEntity(
            title: "roundtrip",
            platformPreset: .instagram(aspect: .portrait, pageCount: 2),
            pages: [PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5))],
            placements: [placement],
            defaultPhotoFrame: FramePreset.thinBlackBorder.photoFrame
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ProjectEntity.self, from: data)
        #expect(decoded == project)
    }
}
