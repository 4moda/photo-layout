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

    /// 写真を保存し、指定ページの空スロットへ当てはめて永続化する（スロット先行UI用）。
    public func executeAssignToSlot(
        project: ProjectEntity, imageData: Data, pageIndex: Int, slot slotIndex: Int
    ) async throws -> ProjectEntity {
        let photo = try await photoStore.store(imageData: imageData)
        var updated = project
        updated.assignPhoto(photo, toPage: pageIndex, slot: slotIndex)
        updated.updatedAt = Date()
        try await repository.save(updated)
        return updated
    }

    /// 写真を保存し、1枚をカルーセルの全スライドへ分割して永続化する（SCRL型・分割UI用）。
    public func executeSplit(
        project: ProjectEntity, imageData: Data, intoSlides count: Int, slideAspect: AspectRatio
    ) async throws -> ProjectEntity {
        let photo = try await photoStore.store(imageData: imageData)
        var updated = project
        updated.splitPhoto(photo, intoSlides: count, slideAspect: slideAspect)
        updated.updatedAt = Date()
        try await repository.save(updated)
        return updated
    }
}
