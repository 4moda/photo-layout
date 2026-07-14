import Foundation

/// プロジェクトを複製して保存する（同じ構図で写真だけ入れ替える連続投稿の起点）。
/// エンティティの複製規則は `ProjectEntity.duplicated()` に集約。
public struct DuplicateProjectUseCase: Sendable {
    private let repository: any ProjectRepository

    public init(repository: any ProjectRepository) {
        self.repository = repository
    }

    public func execute(_ project: ProjectEntity) async throws -> ProjectEntity {
        let copy = project.duplicated()
        try await repository.save(copy)
        return copy
    }
}
