import Foundation

public struct ExportResult: Equatable, Sendable {
    public let pixelSize: LayoutSize
    public let byteCount: Int

    public init(pixelSize: LayoutSize, byteCount: Int) {
        self.pixelSize = pixelSize
        self.byteCount = byteCount
    }
}

/// 1ページを実解像度で書き出し、写真ライブラリへ保存する。
/// サイズ決定→プラン生成→描画→保存のオーケストレーションのみを担い、計算はServicesに委譲。
public struct ExportPageUseCase: Sendable {
    private let renderer: any ImageExporting
    private let librarySaver: any PhotoLibrarySaving

    public init(renderer: any ImageExporting, librarySaver: any PhotoLibrarySaving) {
        self.renderer = renderer
        self.librarySaver = librarySaver
    }

    public func execute(
        project: ProjectEntity,
        pageIndex: Int,
        format: ExportFormat = .defaultJPEG
    ) async throws -> ExportResult {
        guard let page = project.orderedPages.first(where: { $0.index == pageIndex }) else {
            throw ExportError.pageNotFound
        }
        let placements = project.orderedPlacements
        let pixelSize = ExportSizeCalculator.pageSize(page: page, placements: placements)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: placements,
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: pixelSize
        )
        let data = try await renderer.render(plan: plan, pixelSize: pixelSize, format: format)
        try await librarySaver.save(imageData: data)
        return ExportResult(pixelSize: pixelSize, byteCount: data.count)
    }
}

public enum ExportError: Error, Equatable, Sendable {
    case pageNotFound
    case renderingFailed
    case encodingFailed
}
