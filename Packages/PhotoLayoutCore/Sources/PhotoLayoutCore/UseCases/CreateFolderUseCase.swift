import Foundation

/// 新規フォルダを作成する。
public struct CreateFolderUseCase: Sendable {
    private let repository: any FolderRepository

    public init(repository: any FolderRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(name: String) async throws -> FolderEntity {
        let folder = FolderEntity(name: name)
        try await repository.save(folder)
        return folder
    }
}
