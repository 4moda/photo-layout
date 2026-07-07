import Foundation

/// プロジェクト永続化のPort。実装はInfrastructure（SwiftData）が提供する。
public protocol ProjectRepository: Sendable {
    func fetchAll() async throws -> [ProjectEntity]
    func fetch(id: UUID) async throws -> ProjectEntity?
    /// idが既存なら置換、なければ新規作成（upsert）
    func save(_ project: ProjectEntity) async throws
    func delete(id: UUID) async throws
}
