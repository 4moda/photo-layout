import Foundation

/// 写真データを保存し、プロジェクトへ配置して永続化する。
public struct AddPhotoUseCase: Sendable {
    private let photoStore: any PhotoStoring
    private let repository: any ProjectRepository

    public init(photoStore: any PhotoStoring, repository: any ProjectRepository) {
        self.photoStore = photoStore
        self.repository = repository
    }

    public func execute(project: ProjectEntity, imageData: Data, pageIndex: Int = 0) async throws -> ProjectEntity {
        let photo = try await photoStore.store(imageData: imageData)
        var updated = project
        updated.addPhoto(photo, toPage: pageIndex)
        updated.updatedAt = Date()
        try await repository.save(updated)
        return updated
    }
}
