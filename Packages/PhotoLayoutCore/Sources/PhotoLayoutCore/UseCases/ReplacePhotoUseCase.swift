import Foundation

/// 選択中の写真を別の写真へ差し替えて永続化する。
/// 配置（destRect・枠・重なり順・スロット拘束）はそのまま、写真とクロップだけが変わる
/// （クロップの再計算規則は `ProjectEntity.replacePhoto` に集約）。
public struct ReplacePhotoUseCase: Sendable {
    private let photoStore: any PhotoStoring
    private let repository: any ProjectRepository

    public init(photoStore: any PhotoStoring, repository: any ProjectRepository) {
        self.photoStore = photoStore
        self.repository = repository
    }

    /// ロック中などで差し替えられない場合は元のprojectをそのまま返す（保存もしない）。
    public func execute(
        project: ProjectEntity, placementID: UUID, imageData: Data
    ) async throws -> ProjectEntity {
        let photo = try await photoStore.store(imageData: imageData)
        var updated = project
        guard updated.replacePhoto(photo, placementID: placementID) else { return project }
        updated.updatedAt = Date()
        try await repository.save(updated)
        return updated
    }
}
