import Foundation

/// フォルダ名を変更する（updatedAtを更新）。
public struct RenameFolderUseCase: Sendable {
    private let repository: any FolderRepository

    public init(repository: any FolderRepository) {
        self.repository = repository
    }

    @discardableResult
    public func execute(id: UUID, name: String) async throws -> FolderEntity {
        guard var folder = try await repository.fetch(id: id) else {
            throw RenameFolderError.folderNotFound
        }
        folder.name = name
        folder.updatedAt = Date()
        try await repository.save(folder)
        return folder
    }
}

public enum RenameFolderError: Error, Equatable, Sendable {
    case folderNotFound
}
