import Foundation
import Observation
import PhotoLayoutCore

@Observable
@MainActor
final class ProjectListViewModel {
    private(set) var projects: [ProjectEntity] = []
    var errorMessage: String?

    private let listProjects: ListProjectsUseCase
    private let createProject: CreateProjectUseCase
    private let deleteProject: DeleteProjectUseCase
    private let createXPost: CreateXPostUseCase
    /// --seed-demo時のみ注入される（UIテスト・CIスクショ用）
    private let seedDemo: (() async -> Void)?
    private var didSeed = false

    init(
        listProjects: ListProjectsUseCase,
        createProject: CreateProjectUseCase,
        deleteProject: DeleteProjectUseCase,
        createXPost: CreateXPostUseCase,
        seedDemo: (() async -> Void)? = nil
    ) {
        self.listProjects = listProjects
        self.createProject = createProject
        self.deleteProject = deleteProject
        self.createXPost = createXPost
        self.seedDemo = seedDemo
    }

    func load() async {
        if let seedDemo, !didSeed {
            didSeed = true
            await seedDemo()
        }
        do {
            projects = try await listProjects.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDraft() async {
        do {
            _ = try await createProject.execute()
            projects = try await listProjects.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// X投稿プロジェクト作成: 選んだ1〜4枚から枚数別アスペクトのページを自動生成する。
    /// 成功時は作成したプロジェクトを返す（呼び出し側でエディタへ遷移する）。
    func createXPost(imageDataList: [Data]) async -> ProjectEntity? {
        do {
            let project = try await createXPost.execute(imageDataList: imageDataList)
            projects = try await listProjects.execute()
            return project
        } catch {
            errorMessage = "X投稿プロジェクトを作成できませんでした: \(error.localizedDescription)"
            return nil
        }
    }

    func delete(id: UUID) async {
        do {
            try await deleteProject.execute(id: id)
            projects = try await listProjects.execute()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
