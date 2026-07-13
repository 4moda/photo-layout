import Foundation
@testable import PhotoLayoutCore

/// UseCaseテスト用のフェイクRepository。actor化してSwift 6のstrict concurrencyを満たす。
actor InMemoryFolderRepository: FolderRepository {
    private var storage: [UUID: FolderEntity] = [:]

    func fetchAll() async throws -> [FolderEntity] {
        Array(storage.values)
    }

    func fetch(id: UUID) async throws -> FolderEntity? {
        storage[id]
    }

    func save(_ folder: FolderEntity) async throws {
        storage[folder.id] = folder
    }

    func delete(id: UUID) async throws {
        storage[id] = nil
    }
}
