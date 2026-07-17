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
        format: ExportFormat = .defaultJPEG,
        resolution: ExportResolution = .standard
    ) async throws -> ExportResult {
        guard let page = project.page(at: pageIndex) else {
            throw ExportError.pageNotFound
        }
        // 隣スライドからはみ出して重なる写真も含めて描く（プロジェクト配置モデル）
        return try await render(
            page: page,
            placements: SpreadGeometry.visiblePlacements(onPage: pageIndex, project: project),
            textItems: project.textItems(onPage: pageIndex),
            defaultFrame: project.defaultPhotoFrame,
            format: format,
            resolution: resolution
        )
    }

    /// 全ページを投稿順（PageEntity.index順）に書き出して保存する。
    /// カメラロール上でも選択しやすいよう、保存順＝投稿順を保証する。
    public func executeAll(
        project: ProjectEntity,
        format: ExportFormat = .defaultJPEG,
        resolution: ExportResolution = .standard
    ) async throws -> [ExportResult] {
        var results: [ExportResult] = []
        for page in project.orderedPages {
            results.append(try await execute(
                project: project, pageIndex: page.index, format: format, resolution: resolution))
        }
        return results
    }

    /// 1ページを実解像度で書き出し、カメラロールへは保存せず画像Dataを返す（共有シート用）。
    /// レンダリングは`execute`と同じ経路（RenderPlanBuilder→ImageExporting）を再利用する。
    public func renderImageData(
        project: ProjectEntity,
        pageIndex: Int,
        format: ExportFormat = .defaultJPEG,
        resolution: ExportResolution = .standard
    ) async throws -> Data {
        guard let page = project.page(at: pageIndex) else {
            throw ExportError.pageNotFound
        }
        return try await renderData(
            page: page,
            placements: SpreadGeometry.visiblePlacements(onPage: pageIndex, project: project),
            textItems: project.textItems(onPage: pageIndex),
            defaultFrame: project.defaultPhotoFrame,
            format: format,
            resolution: resolution
        ).data
    }

    /// 全ページを投稿順に書き出し、カメラロールへは保存せず画像Dataの配列を返す（共有シート用）。
    public func renderAllImageData(
        project: ProjectEntity,
        format: ExportFormat = .defaultJPEG,
        resolution: ExportResolution = .standard
    ) async throws -> [Data] {
        var results: [Data] = []
        for page in project.orderedPages {
            results.append(try await renderImageData(
                project: project, pageIndex: page.index, format: format, resolution: resolution))
        }
        return results
    }

    /// X組写真の書き出し: 1ページ上の各配置（スロット）を個別の実解像度画像として書き出す。
    /// スロット間のガター・ページ余白は含めず、各画像はスロットの内容を縁いっぱいに描く
    /// （写真ごとの枠線は保持される）。保存順＝表示順（sortIndex順）＝X投稿順。
    public func executeSlots(
        project: ProjectEntity,
        pageIndex: Int,
        format: ExportFormat = .defaultJPEG,
        resolution: ExportResolution = .standard
    ) async throws -> [ExportResult] {
        guard let page = project.page(at: pageIndex) else {
            throw ExportError.pageNotFound
        }
        var results: [ExportResult] = []
        for placement in project.placements(onPage: pageIndex) {
            // スロットを1枚の仮想ページとして扱う（余白なし・スロットのpxアスペクト）
            let slotPixelAspect = placement.destRect.aspectRatio * page.contentAspect
            let slotPage = PageEntity(
                index: 0,
                aspect: AspectRatio(width: slotPixelAspect, height: 1),
                background: .plainWhite
            )
            var slotPlacement = placement
            slotPlacement.destRect = .unit
            slotPlacement.pageIndex = 0
            results.append(try await render(
                page: slotPage,
                placements: [slotPlacement],
                defaultFrame: project.defaultPhotoFrame,
                format: format,
                resolution: resolution
            ))
        }
        return results
    }

    private func render(
        page: PageEntity,
        placements: [PlacementEntity],
        textItems: [TextItemEntity] = [],
        defaultFrame: PhotoFrameStyle,
        format: ExportFormat,
        resolution: ExportResolution
    ) async throws -> ExportResult {
        let rendered = try await renderData(
            page: page,
            placements: placements,
            textItems: textItems,
            defaultFrame: defaultFrame,
            format: format,
            resolution: resolution
        )
        try await librarySaver.save(imageData: rendered.data)
        return ExportResult(pixelSize: rendered.pixelSize, byteCount: rendered.data.count)
    }

    /// サイズ決定→プラン生成→描画のみを行い、保存はしない。`execute`系と`renderImageData`系の共通経路。
    private func renderData(
        page: PageEntity,
        placements: [PlacementEntity],
        textItems: [TextItemEntity] = [],
        defaultFrame: PhotoFrameStyle,
        format: ExportFormat,
        resolution: ExportResolution
    ) async throws -> (data: Data, pixelSize: LayoutSize) {
        let pixelSize = ExportSizeCalculator.pageSize(
            page: page, placements: placements, resolution: resolution)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: placements,
            textItems: textItems,
            defaultFrame: defaultFrame,
            pagePixelSize: pixelSize
        )
        let data = try await renderer.render(plan: plan, pixelSize: pixelSize, format: format)
        return (data, pixelSize)
    }
}

public enum ExportError: Error, Equatable, Sendable {
    case pageNotFound
    case renderingFailed
    case encodingFailed
}
