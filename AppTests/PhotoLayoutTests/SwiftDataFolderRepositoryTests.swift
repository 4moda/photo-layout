import XCTest
import SwiftData
import PhotoLayoutCore
@testable import PhotoLayout

/// SwiftDataFolderRepositoryの往復テスト（in-memoryストア）。
@MainActor
final class SwiftDataFolderRepositoryTests: XCTestCase {
    // コンテナを保持しないとsetUp終了時に解放され、以降のcontext操作がクラッシュする
    private var container: ModelContainer!
    private var repository: SwiftDataFolderRepository!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: ProjectModel.self, PageModel.self, PlacementModel.self, FolderModel.self,
            configurations: config
        )
        repository = SwiftDataFolderRepository(modelContext: container.mainContext)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
    }

    private func makeSampleFolder() -> FolderEntity {
        FolderEntity(
            name: "旅行",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    func testSaveFetchRoundTrip() async throws {
        let folder = makeSampleFolder()
        try await repository.save(folder)

        let fetched = try await repository.fetch(id: folder.id)
        XCTAssertEqual(fetched, folder)
    }

    func testUpsertReplacesExisting() async throws {
        var folder = makeSampleFolder()
        try await repository.save(folder)

        folder.name = "更新後"
        try await repository.save(folder)

        let fetched = try await repository.fetch(id: folder.id)
        let all = try await repository.fetchAll()
        XCTAssertEqual(fetched?.name, "更新後")
        XCTAssertEqual(all.count, 1)
    }

    func testFetchAll() async throws {
        try await repository.save(FolderEntity(name: "A"))
        try await repository.save(FolderEntity(name: "B"))

        let all = try await repository.fetchAll()
        XCTAssertEqual(Set(all.map(\.name)), ["A", "B"])
    }

    func testDelete() async throws {
        let folder = makeSampleFolder()
        try await repository.save(folder)
        try await repository.delete(id: folder.id)

        let fetched = try await repository.fetch(id: folder.id)
        let all = try await repository.fetchAll()
        XCTAssertNil(fetched)
        XCTAssertTrue(all.isEmpty)
    }
}
