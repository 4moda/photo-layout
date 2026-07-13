import Foundation

/// フォルダ一覧を更新日時の新しい順で返す。
public struct ListFoldersUseCase: Sendable {
    private let repository: any FolderRepository

    public init(repository: any FolderRepository) {
        self.repository = repository
    }

    public func execute() async throws -> [FolderEntity] {
        try await repository.fetchAll().sorted { $0.updatedAt > $1.updatedAt }
    }
}
