import Foundation

/// フォルダ削除の挙動。呼び出し元（UI）は必ずどちらか一方を明示的に選ぶ。
public enum DeleteFolderMode: Sendable {
    /// フォルダのみ削除する。属していた各プロジェクトは削除せず、folderIDをnilに戻す（未分類として残る）
    case folderOnly
    /// フォルダと、属していた各プロジェクトをまとめて削除する
    case cascade
}

public struct DeleteFolderUseCase: Sendable {
    private let folderRepository: any FolderRepository
    private let projectRepository: any ProjectRepository

    public init(folderRepository: any FolderRepository, projectRepository: any ProjectRepository) {
        self.folderRepository = folderRepository
        self.projectRepository = projectRepository
    }

    public func execute(id: UUID, mode: DeleteFolderMode) async throws {
        let projectsInFolder = try await projectRepository.fetchAll().filter { $0.folderID == id }
        switch mode {
        case .folderOnly:
            for var project in projectsInFolder {
                project.folderID = nil
                try await projectRepository.save(project)
            }
        case .cascade:
            for project in projectsInFolder {
                try await projectRepository.delete(id: project.id)
            }
        }
        try await folderRepository.delete(id: id)
    }
}
