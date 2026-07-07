import Foundation
import SwiftData

/// ProjectEntityの永続化表現。スタイル等の複合値はJSON Dataで保持し、
/// SwiftDataのCodable格納の実装差異に依存しない（マッピングはSwiftDataProjectRepository）。
@Model
final class ProjectModel {
    @Attribute(.unique) var id: UUID
    var title: String?
    var presetData: Data?
    var defaultFrameData: Data
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PageModel.project)
    var pages: [PageModel] = []

    @Relationship(deleteRule: .cascade, inverse: \PlacementModel.project)
    var placements: [PlacementModel] = []

    init(
        id: UUID,
        title: String?,
        presetData: Data?,
        defaultFrameData: Data,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.presetData = presetData
        self.defaultFrameData = defaultFrameData
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PageModel {
    @Attribute(.unique) var id: UUID
    var index: Int
    var aspectWidth: Double
    var aspectHeight: Double
    var backgroundData: Data
    var project: ProjectModel?

    init(id: UUID, index: Int, aspectWidth: Double, aspectHeight: Double, backgroundData: Data) {
        self.id = id
        self.index = index
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.backgroundData = backgroundData
    }
}

@Model
final class PlacementModel {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    var photoFileName: String
    var photoPixelWidth: Int
    var photoPixelHeight: Int
    var cropX: Double
    var cropY: Double
    var cropWidth: Double
    var cropHeight: Double
    var destX: Double
    var destY: Double
    var destWidth: Double
    var destHeight: Double
    var frameOverrideData: Data?
    var project: ProjectModel?

    init(
        id: UUID,
        sortIndex: Int,
        photoFileName: String,
        photoPixelWidth: Int,
        photoPixelHeight: Int,
        cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double,
        destX: Double, destY: Double, destWidth: Double, destHeight: Double,
        frameOverrideData: Data?
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.photoFileName = photoFileName
        self.photoPixelWidth = photoPixelWidth
        self.photoPixelHeight = photoPixelHeight
        self.cropX = cropX
        self.cropY = cropY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.destX = destX
        self.destY = destY
        self.destWidth = destWidth
        self.destHeight = destHeight
        self.frameOverrideData = frameOverrideData
    }
}
