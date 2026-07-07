import Foundation
@testable import PhotoLayoutCore

/// UseCaseテスト用のフェイクRepository。actor化してSwift 6のstrict concurrencyを満たす。
actor InMemoryProjectRepository: ProjectRepository {
    private var storage: [UUID: ProjectEntity] = [:]

    func fetchAll() async throws -> [ProjectEntity] {
        Array(storage.values)
    }

    func fetch(id: UUID) async throws -> ProjectEntity? {
        storage[id]
    }

    func save(_ project: ProjectEntity) async throws {
        storage[project.id] = project
    }

    func delete(id: UUID) async throws {
        storage[id] = nil
    }
}
