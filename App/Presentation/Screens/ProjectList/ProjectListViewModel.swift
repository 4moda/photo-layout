import Foundation
import Observation
import UIKit
import PhotoLayoutCore

@Observable
@MainActor
final class ProjectListViewModel {
    private(set) var projects: [ProjectEntity] = []
    var errorMessage: String?

    private let listProjects: ListProjectsUseCase
    private let createProject: CreateProjectUseCase
    private let deleteProject: DeleteProjectUseCase
    /// 一覧サムネイル用の小さいデコード（256px上限）を注入する
    private let thumbnailProvider: any PreviewImageProviding
    /// projectID → (更新日時, 1ページ目の配置画像)。updatedAtが変わったら作り直す
    private var thumbnailCache: [UUID: (updatedAt: Date, images: [UUID: UIImage])] = [:]
    /// --seed-demo時のみ注入される（UIテスト・CIスクショ用）
    private let seedDemo: (() async -> Void)?
    private var didSeed = false

    init(
        listProjects: ListProjectsUseCase,
        createProject: CreateProjectUseCase,
        deleteProject: DeleteProjectUseCase,
        thumbnailProvider: any PreviewImageProviding,
        seedDemo: (() async -> Void)? = nil
    ) {
        self.listProjects = listProjects
        self.createProject = createProject
        self.deleteProject = deleteProject
        self.thumbnailProvider = thumbnailProvider
        self.seedDemo = seedDemo
    }

    func load() async {
        if let seedDemo, !didSeed {
            didSeed = true
            await seedDemo()
        }
        do {
            projects = try await listProjects.execute()
            await refreshThumbnails()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 1ページ目のサムネイル描画に使う画像（未生成なら空）
    func thumbnailImages(for project: ProjectEntity) -> [UUID: UIImage] {
        thumbnailCache[project.id]?.images ?? [:]
    }

    private func refreshThumbnails() async {
        for project in projects {
            if let cached = thumbnailCache[project.id], cached.updatedAt == project.updatedAt {
                continue
            }
            // 1ページ目の配置だけデコードする
            var firstPageOnly = project
            let firstIndex = project.orderedPages.first?.index ?? 0
            firstPageOnly.placements = project.placements(onPage: firstIndex)
            let images = await thumbnailProvider.previewImages(project: firstPageOnly)
            thumbnailCache[project.id] = (project.updatedAt, images)
        }
        // 消えたプロジェクトのキャッシュを掃除
        let ids = Set(projects.map(\.id))
        thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
    }

    /// 新規プロジェクト作成。用紙サイズ（キャンバスのアスペクト）だけ決め、写真は後から
    /// エディタ内で追加する（一覧では写真選択を誘導しない）。枠付けもレイアウトも同じ
    /// 汎用プロジェクト — 1枚＋余白なら枠付け、複数枚＋テンプレートならレイアウトになる。
    /// 成功時は作成したプロジェクトを返す（呼び出し側でエディタへ遷移する）。
    func create(aspect: AspectRatio, title: String?) async -> ProjectEntity? {
        do {
            let project = try await createProject.execute(title: title, aspect: aspect)
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
