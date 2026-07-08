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
    /// --seed-demo時のみ注入される（UIテスト・CIスクショ用）
    private let seedDemo: (() async -> Void)?
    private var didSeed = false

    init(
        listProjects: ListProjectsUseCase,
        createProject: CreateProjectUseCase,
        deleteProject: DeleteProjectUseCase,
        seedDemo: (() async -> Void)? = nil
    ) {
        self.listProjects = listProjects
        self.createProject = createProject
        self.deleteProject = deleteProject
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

    /// 新規プロジェクト作成。写真は後からエディタ内で追加する（一覧では選ばせない）。
    /// 成功時は作成したプロジェクトを返す（呼び出し側でエディタへ遷移する）。
    func create(preset: PlatformPreset?, title: String?) async -> ProjectEntity? {
        do {
            let project = try await createProject.execute(title: title, preset: preset)
            projects = try await listProjects.execute()
            return project
        } catch {
            errorMessage = error.localizedDescription
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
