import Foundation

/// 下書き一覧を更新日時の新しい順で返す。
public struct ListProjectsUseCase: Sendable {
    private let repository: any ProjectRepository

    public init(repository: any ProjectRepository) {
        self.repository = repository
    }

    public func execute() async throws -> [ProjectEntity] {
        try await repository.fetchAll().sorted { $0.updatedAt > $1.updatedAt }
    }
}
