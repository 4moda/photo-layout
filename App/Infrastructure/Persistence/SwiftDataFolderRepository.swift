import Foundation
import SwiftData
import PhotoLayoutCore

/// FolderRepositoryのSwiftData実装。Model⇄Entityのマッピングを一手に担う。
/// saveはupsert（既存idは先に削除してから再挿入。ProjectRepositoryと同じ設計）。
@MainActor
final class SwiftDataFolderRepository: FolderRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [FolderEntity] {
        let models = try modelContext.fetch(FetchDescriptor<FolderModel>())
        return models.map(entity(from:))
    }

    func fetch(id: UUID) async throws -> FolderEntity? {
        try fetchModel(id: id).map(entity(from:))
    }

    func save(_ folder: FolderEntity) async throws {
        if let existing = try fetchModel(id: folder.id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
        modelContext.insert(FolderModel(
            id: folder.id,
            name: folder.name,
            createdAt: folder.createdAt,
            updatedAt: folder.updatedAt
        ))
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        if let existing = try fetchModel(id: id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Mapping

    private func fetchModel(id: UUID) throws -> FolderModel? {
        var descriptor = FetchDescriptor<FolderModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func entity(from model: FolderModel) -> FolderEntity {
        FolderEntity(id: model.id, name: model.name, createdAt: model.createdAt, updatedAt: model.updatedAt)
    }
}
