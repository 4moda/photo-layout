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
    // 所属フォルダのid。未分類はnil。既存ストアからの軽量マイグレーションのためnil既定
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PageModel.project)
    var pages: [PageModel] = []

    @Relationship(deleteRule: .cascade, inverse: \PlacementModel.project)
    var placements: [PlacementModel] = []

    @Relationship(deleteRule: .cascade, inverse: \TextItemModel.project)
    var textItems: [TextItemModel] = []

    init(
        id: UUID,
        title: String?,
        presetData: Data?,
        defaultFrameData: Data,
        folderID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.presetData = presetData
        self.defaultFrameData = defaultFrameData
        self.folderID = folderID
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
    // テンプレートのスロット矩形 [LayoutRect]? のJSON。既存ストアからの軽量マイグレーションのためnil既定
    var slotsData: Data?
    var project: ProjectModel?

    init(id: UUID, index: Int, aspectWidth: Double, aspectHeight: Double, backgroundData: Data, slotsData: Data? = nil) {
        self.id = id
        self.index = index
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.backgroundData = backgroundData
        self.slotsData = slotsData
    }
}

@Model
final class PlacementModel {
    @Attribute(.unique) var id: UUID
    var sortIndex: Int
    // 既存ストアからの軽量マイグレーションのため既定値を持つ
    var pageIndex: Int = 0
    // どのスロットに入っているか（PageEntity.slots のindex）。nil=スロット非拘束
    var slotIndex: Int?
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
    // 既存ストアからの軽量マイグレーションのため既定値を持つ（0=回転なし）
    var cropRotation: Double = 0
    var frameOverrideData: Data?
    // 既存ストアからの軽量マイグレーションのため既定値を持つ（false=未ロック）
    var isLocked: Bool = false
    var project: ProjectModel?

    init(
        id: UUID,
        sortIndex: Int,
        pageIndex: Int,
        slotIndex: Int?,
        photoFileName: String,
        photoPixelWidth: Int,
        photoPixelHeight: Int,
        cropX: Double, cropY: Double, cropWidth: Double, cropHeight: Double,
        destX: Double, destY: Double, destWidth: Double, destHeight: Double,
        cropRotation: Double,
        frameOverrideData: Data?,
        isLocked: Bool = false
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.pageIndex = pageIndex
        self.slotIndex = slotIndex
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
        self.cropRotation = cropRotation
        self.frameOverrideData = frameOverrideData
        self.isLocked = isLocked
    }
}

@Model
final class TextItemModel {
    @Attribute(.unique) var id: UUID
    var pageIndex: Int
    var sortIndex: Int
    var content: String
    var x: Double
    var y: Double
    var fontSizeRatio: Double
    var colorRed: Double
    var colorGreen: Double
    var colorBlue: Double
    var colorAlpha: Double
    var project: ProjectModel?

    init(
        id: UUID,
        pageIndex: Int,
        sortIndex: Int,
        content: String,
        x: Double,
        y: Double,
        fontSizeRatio: Double,
        colorRed: Double,
        colorGreen: Double,
        colorBlue: Double,
        colorAlpha: Double
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.sortIndex = sortIndex
        self.content = content
        self.x = x
        self.y = y
        self.fontSizeRatio = fontSizeRatio
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.colorAlpha = colorAlpha
    }
}
