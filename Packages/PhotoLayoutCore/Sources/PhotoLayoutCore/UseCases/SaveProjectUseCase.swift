import Foundation

/// 編集後のプロジェクトを保存する（updatedAtを更新）。
public struct SaveProjectUseCase: Sendable {
    private let repository: any ProjectRepository

    public init(repository: any ProjectRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(_ project: ProjectEntity) async throws -> ProjectEntity {
        var updated = project
        updated.updatedAt = Date()
        try await repository.save(updated)
        return updated
    }
}
