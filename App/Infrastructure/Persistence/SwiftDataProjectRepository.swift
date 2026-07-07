import Foundation
import SwiftData
import PhotoLayoutCore

/// ProjectRepositoryのSwiftData実装。Model⇄Entityのマッピングを一手に担う。
/// saveはupsert（既存idは子ごと削除して再挿入。v1のシンプルさ優先）。
@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private let modelContext: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() async throws -> [ProjectEntity] {
        let models = try modelContext.fetch(FetchDescriptor<ProjectModel>())
        return try models.map(entity(from:))
    }

    func fetch(id: UUID) async throws -> ProjectEntity? {
        try fetchModel(id: id).map(entity(from:))
    }

    func save(_ project: ProjectEntity) async throws {
        // upsert: 既存があれば先に削除を確定させ、unique制約(id)の衝突を避ける
        if let existing = try fetchModel(id: project.id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
        // SwiftDataは未insertモデルへのリレーション代入でクラッシュしうるため、
        // 親をinsertしてから子配列を代入する（子は自動insertされる）
        let model = ProjectModel(
            id: project.id,
            title: project.title,
            presetData: try project.platformPreset.map { try encoder.encode($0) },
            defaultFrameData: try encoder.encode(project.defaultPhotoFrame),
            createdAt: project.createdAt,
            updatedAt: project.updatedAt
        )
        modelContext.insert(model)
        model.pages = try project.pages.map(pageModel(from:))
        model.placements = try project.placements.map(placementModel(from:))
        try modelContext.save()
    }

    func delete(id: UUID) async throws {
        if let existing = try fetchModel(id: id) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    // MARK: - Mapping

    private func fetchModel(id: UUID) throws -> ProjectModel? {
        var descriptor = FetchDescriptor<ProjectModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func entity(from model: ProjectModel) throws -> ProjectEntity {
        ProjectEntity(
            id: model.id,
            title: model.title,
            platformPreset: try model.presetData.map { try decoder.decode(PlatformPreset.self, from: $0) },
            pages: try model.pages
                .sorted { $0.index < $1.index }
                .map { page in
                    PageEntity(
                        id: page.id,
                        index: page.index,
                        aspect: AspectRatio(width: page.aspectWidth, height: page.aspectHeight),
                        background: try decoder.decode(CanvasBackgroundStyle.self, from: page.backgroundData)
                    )
                },
            placements: try model.placements
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { placement in
                    PlacementEntity(
                        id: placement.id,
                        sortIndex: placement.sortIndex,
                        photo: PhotoRef(
                            fileName: placement.photoFileName,
                            pixelWidth: placement.photoPixelWidth,
                            pixelHeight: placement.photoPixelHeight
                        ),
                        cropRect: LayoutRect(
                            x: placement.cropX, y: placement.cropY,
                            width: placement.cropWidth, height: placement.cropHeight
                        ),
                        contentMode: ContentMode(rawValue: placement.contentModeRaw) ?? .fill,
                        destRect: LayoutRect(
                            x: placement.destX, y: placement.destY,
                            width: placement.destWidth, height: placement.destHeight
                        ),
                        frameOverride: try placement.frameOverrideData.map {
                            try decoder.decode(PhotoFrameStyle.self, from: $0)
                        }
                    )
                },
            defaultPhotoFrame: try decoder.decode(PhotoFrameStyle.self, from: model.defaultFrameData),
            createdAt: model.createdAt,
            updatedAt: model.updatedAt
        )
    }

    private func pageModel(from page: PageEntity) throws -> PageModel {
        PageModel(
            id: page.id,
            index: page.index,
            aspectWidth: page.aspect.width,
            aspectHeight: page.aspect.height,
            backgroundData: try encoder.encode(page.background)
        )
    }

    private func placementModel(from placement: PlacementEntity) throws -> PlacementModel {
        PlacementModel(
            id: placement.id,
            sortIndex: placement.sortIndex,
            photoFileName: placement.photo.fileName,
            photoPixelWidth: placement.photo.pixelWidth,
            photoPixelHeight: placement.photo.pixelHeight,
            cropX: placement.cropRect.x, cropY: placement.cropRect.y,
            cropWidth: placement.cropRect.width, cropHeight: placement.cropRect.height,
            contentModeRaw: placement.contentMode.rawValue,
            destX: placement.destRect.x, destY: placement.destRect.y,
            destWidth: placement.destRect.width, destHeight: placement.destRect.height,
            frameOverrideData: try placement.frameOverride.map { try encoder.encode($0) }
        )
    }
}
