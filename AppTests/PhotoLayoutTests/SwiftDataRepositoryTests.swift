import XCTest
import SwiftData
import PhotoLayoutCore
@testable import PhotoLayout

/// SwiftDataProjectRepositoryの往復テスト（in-memoryストア）。
/// Entity → Model → Entity が完全一致することを保証する。
@MainActor
final class SwiftDataRepositoryTests: XCTestCase {
    // コンテナを保持しないとsetUp終了時に解放され、以降のcontext操作がクラッシュする
    private var container: ModelContainer!
    private var repository: SwiftDataProjectRepository!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ProjectModel.self, PageModel.self, PlacementModel.self,
            configurations: config
        )
        repository = SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
    }

    private func makeSampleProject() -> ProjectEntity {
        ProjectEntity(
            title: "作例",
            platformPreset: .x(photoCount: 3),
            pages: PlatformSpecTable.xPageAspects(photoCount: 3).enumerated().map { index, aspect in
                PageEntity(index: index, aspect: aspect, background: FramePreset.whiteMargin.background)
            },
            placements: [
                PlacementEntity(
                    sortIndex: 0,
                    photo: PhotoRef(fileName: "a.jpg", pixelWidth: 4000, pixelHeight: 6000),
                    cropRect: LayoutRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4),
                    destRect: LayoutRect(x: 0, y: 0, width: 1, height: 1),
                    cropRotation: 12.5,
                    frameOverride: FramePreset.blackBackgroundWhiteBorder.photoFrame
                ),
                PlacementEntity(
                    sortIndex: 1,
                    pageIndex: 2,
                    photo: PhotoRef(fileName: "b.jpg", pixelWidth: 6000, pixelHeight: 4000),
                    destRect: LayoutRect(x: 1, y: 0, width: 1, height: 1)
                )
            ],
            defaultPhotoFrame: FramePreset.thinBlackBorder.photoFrame,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    func testSaveFetchRoundTrip() async throws {
        let project = makeSampleProject()
        try await repository.save(project)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertEqual(fetched, project)
    }

    func testFolderIDRoundTrip() async throws {
        var project = makeSampleProject()
        project.folderID = UUID()
        try await repository.save(project)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertEqual(fetched?.folderID, project.folderID)
    }

    func testFolderIDDefaultsToNil() async throws {
        let project = makeSampleProject()
        XCTAssertNil(project.folderID)
        try await repository.save(project)

        let fetched = try await repository.fetch(id: project.id)
        XCTAssertNil(fetched?.folderID)
    }

    func testUpsertReplacesExisting() async throws {
        var project = makeSampleProject()
        try await repository.save(project)

        project.title = "更新後"
        project.placements.removeLast()
        try await repository.save(project)

        let fetched = try await repository.fetch(id: project.id)
        let all = try await repository.fetchAll()
        XCTAssertEqual(fetched?.title, "更新後")
        XCTAssertEqual(fetched?.placements.count, 1)
        XCTAssertEqual(all.count, 1)
    }

    func testDelete() async throws {
        let project = makeSampleProject()
        try await repository.save(project)
        try await repository.delete(id: project.id)

        let fetched = try await repository.fetch(id: project.id)
        let all = try await repository.fetchAll()
        XCTAssertNil(fetched)
        XCTAssertTrue(all.isEmpty)
    }
}
