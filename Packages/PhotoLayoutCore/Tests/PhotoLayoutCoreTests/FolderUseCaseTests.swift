import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("Folder UseCases（フェイクRepository注入）")
struct FolderUseCaseTests {
    @Test("作成したフォルダをfetchで取得できる")
    func createFolder() async throws {
        let repo = InMemoryFolderRepository()
        let created = try await CreateFolderUseCase(repository: repo).execute(name: "旅行")

        let fetched = try await repo.fetch(id: created.id)
        #expect(fetched == created)
        #expect(created.name == "旅行")
    }

    @Test("一覧は更新日時の降順")
    func listSortedByUpdatedAt() async throws {
        let repo = InMemoryFolderRepository()
        let old = FolderEntity(name: "old", updatedAt: Date(timeIntervalSince1970: 1000))
        let new = FolderEntity(name: "new", updatedAt: Date(timeIntervalSince1970: 2000))
        try await repo.save(old)
        try await repo.save(new)

        let listed = try await ListFoldersUseCase(repository: repo).execute()
        #expect(listed.map(\.name) == ["new", "old"])
    }

    @Test("名称変更でnameとupdatedAtが更新される")
    func renameFolder() async throws {
        let repo = InMemoryFolderRepository()
        let created = try await CreateFolderUseCase(repository: repo)
            .execute(name: "旧名")
        var renamed = created
        renamed.updatedAt = Date(timeIntervalSince1970: 0)
        try await repo.save(renamed)

        let result = try await RenameFolderUseCase(repository: repo).execute(id: created.id, name: "新名")
        #expect(result.name == "新名")
        #expect(result.updatedAt > renamed.updatedAt)
        let fetched = try await repo.fetch(id: created.id)
        #expect(fetched?.name == "新名")
    }

    @Test("存在しないフォルダの名称変更はエラー")
    func renameMissingFolderThrows() async throws {
        let repo = InMemoryFolderRepository()
        await #expect(throws: RenameFolderError.folderNotFound) {
            try await RenameFolderUseCase(repository: repo).execute(id: UUID(), name: "新名")
        }
    }

    @Test("プロジェクトをフォルダへ移動し、SaveProjectUseCase経由でfolderIDが永続化される")
    func moveProjectIntoFolder() async throws {
        let projectRepo = InMemoryProjectRepository()
        let folderRepo = InMemoryFolderRepository()
        let project = try await CreateProjectUseCase(repository: projectRepo).execute()
        let folder = try await CreateFolderUseCase(repository: folderRepo).execute(name: "旅行")

        let moved = try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: project.id, folderID: folder.id)
        #expect(moved.folderID == folder.id)
        let fetched = try await projectRepo.fetch(id: project.id)
        #expect(fetched?.folderID == folder.id)
    }

    @Test("folderIDにnilを渡すと未分類へ戻る")
    func moveProjectBackToUnfiled() async throws {
        let projectRepo = InMemoryProjectRepository()
        let folderRepo = InMemoryFolderRepository()
        let project = try await CreateProjectUseCase(repository: projectRepo).execute()
        let folder = try await CreateFolderUseCase(repository: folderRepo).execute(name: "旅行")
        try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: project.id, folderID: folder.id)

        let moved = try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: project.id, folderID: nil)
        #expect(moved.folderID == nil)
    }

    @Test("存在しないプロジェクトの移動はエラー")
    func moveMissingProjectThrows() async throws {
        let projectRepo = InMemoryProjectRepository()
        await #expect(throws: MoveProjectToFolderError.projectNotFound) {
            try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
                .execute(projectID: UUID(), folderID: nil)
        }
    }

    @Test("folderOnly削除: フォルダは消え、所属プロジェクトはfolderIDがnilに戻り残る")
    func deleteFolderOnly() async throws {
        let projectRepo = InMemoryProjectRepository()
        let folderRepo = InMemoryFolderRepository()
        let folder = try await CreateFolderUseCase(repository: folderRepo).execute(name: "旅行")
        let projectA = try await CreateProjectUseCase(repository: projectRepo).execute(title: "A")
        let projectB = try await CreateProjectUseCase(repository: projectRepo).execute(title: "B")
        try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: projectA.id, folderID: folder.id)
        try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: projectB.id, folderID: folder.id)

        try await DeleteFolderUseCase(folderRepository: folderRepo, projectRepository: projectRepo)
            .execute(id: folder.id, mode: .folderOnly)

        #expect(try await folderRepo.fetch(id: folder.id) == nil)
        let remaining = try await projectRepo.fetchAll()
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { $0.folderID == nil })
    }

    @Test("cascade削除: フォルダと所属プロジェクトがまとめて消える。無関係なプロジェクトは残る")
    func deleteFolderCascade() async throws {
        let projectRepo = InMemoryProjectRepository()
        let folderRepo = InMemoryFolderRepository()
        let folder = try await CreateFolderUseCase(repository: folderRepo).execute(name: "旅行")
        let inFolder = try await CreateProjectUseCase(repository: projectRepo).execute(title: "in")
        let unrelated = try await CreateProjectUseCase(repository: projectRepo).execute(title: "unrelated")
        try await MoveProjectToFolderUseCase(projectRepository: projectRepo)
            .execute(projectID: inFolder.id, folderID: folder.id)

        try await DeleteFolderUseCase(folderRepository: folderRepo, projectRepository: projectRepo)
            .execute(id: folder.id, mode: .cascade)

        #expect(try await folderRepo.fetch(id: folder.id) == nil)
        #expect(try await projectRepo.fetch(id: inFolder.id) == nil)
        let remaining = try await projectRepo.fetchAll()
        #expect(remaining.map(\.id) == [unrelated.id])
    }
}
