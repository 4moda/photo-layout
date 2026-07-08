import Foundation

/// X投稿プロジェクトを写真から作る:
/// 1〜4枚の写真を受け取り、枚数別アスペクトのページを自動生成して各ページへ全面配置する。
public struct CreateXPostUseCase: Sendable {
    private let photoStore: any PhotoStoring
    private let repository: any ProjectRepository

    public init(photoStore: any PhotoStoring, repository: any ProjectRepository) {
        self.photoStore = photoStore
        self.repository = repository
    }

    public func execute(
        imageDataList: [Data],
        framePreset: FramePreset = .none
    ) async throws -> ProjectEntity {
        let count = imageDataList.count
        guard (1...PlatformSpecTable.xMaxPhotoCount).contains(count) else {
            throw CreateXPostError.invalidPhotoCount(count)
        }

        let aspects = PlatformSpecTable.xPageAspects(photoCount: count)
        var project = ProjectEntity(
            title: "X投稿（\(count)枚）",
            platformPreset: .x(photoCount: count),
            pages: aspects.enumerated().map { index, aspect in
                PageEntity(index: index, aspect: aspect, background: framePreset.background)
            },
            defaultPhotoFrame: framePreset.photoFrame
        )

        for (index, data) in imageDataList.enumerated() {
            let photo = try await photoStore.store(imageData: data)
            project.addPhoto(photo, toPage: index)
        }

        try await repository.save(project)
        return project
    }
}

public enum CreateXPostError: Error, Equatable, Sendable {
    case invalidPhotoCount(Int)
}
