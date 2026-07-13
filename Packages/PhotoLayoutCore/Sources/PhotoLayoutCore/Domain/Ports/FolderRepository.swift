import Foundation

/// フォルダ永続化のPort。実装はInfrastructure（SwiftData）が提供する。
public protocol FolderRepository: Sendable {
    func fetchAll() async throws -> [FolderEntity]
    func fetch(id: UUID) async throws -> FolderEntity?
    /// idが既存なら置換、なければ新規作成（upsert）
    func save(_ folder: FolderEntity) async throws
    func delete(id: UUID) async throws
}
