import Foundation

/// プロジェクトの所属フォルダを設定・解除する。folderIDにnilを渡すと未分類に戻る。
/// 永続化は既存のSaveProjectUseCase経由で行う（updatedAtの更新もそちらに委ねる）。
public struct MoveProjectToFolderUseCase: Sendable {
    private let projectRepository: any ProjectRepository

    public init(projectRepository: any ProjectRepository) {
        self.projectRepository = projectRepository
    }

    @discardableResult
    public func execute(projectID: UUID, folderID: UUID?) async throws -> ProjectEntity {
        guard var project = try await projectRepository.fetch(id: projectID) else {
            throw MoveProjectToFolderError.projectNotFound
        }
        project.folderID = folderID
        return try await SaveProjectUseCase(repository: projectRepository).execute(project)
    }
}

public enum MoveProjectToFolderError: Error, Equatable, Sendable {
    case projectNotFound
}
