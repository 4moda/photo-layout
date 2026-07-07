import Foundation

/// 新規プロジェクトを作成する。プリセット指定時はPlatformSpecTableからページ構成を生成する。
public struct CreateProjectUseCase: Sendable {
    private let repository: any ProjectRepository

    public init(repository: any ProjectRepository) {
        self.repository = repository
    }

    public func execute(
        title: String? = nil,
        preset: PlatformPreset? = nil,
        framePreset: FramePreset = .none
    ) async throws -> ProjectEntity {
        let aspects: [AspectRatio]
        if let preset {
            aspects = PlatformSpecTable.pageAspects(for: preset)
        } else {
            // プリセットなしの既定はInstagram縦長1ページ（最も使用頻度が高い想定）
            aspects = [PlatformSpecTable.instagramAspect(.portrait)]
        }

        let pages = aspects.enumerated().map { index, aspect in
            PageEntity(index: index, aspect: aspect, background: framePreset.background)
        }

        let project = ProjectEntity(
            title: title,
            platformPreset: preset,
            pages: pages,
            defaultPhotoFrame: framePreset.photoFrame
        )
        try await repository.save(project)
        return project
    }
}
