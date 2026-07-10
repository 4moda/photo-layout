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
        guard let page = project.page(at: pageIndex) else {
            throw ExportError.pageNotFound
        }
        // 隣スライドからはみ出して重なる写真も含めて描く（プロジェクト配置モデル）
        return try await render(
            page: page,
            placements: SpreadGeometry.visiblePlacements(onPage: pageIndex, project: project),
            defaultFrame: project.defaultPhotoFrame,
            format: format
        )
    }

    /// 全ページを投稿順（PageEntity.index順）に書き出して保存する。
    /// カメラロール上でも選択しやすいよう、保存順＝投稿順を保証する。
    public func executeAll(
        project: ProjectEntity,
        format: ExportFormat = .defaultJPEG
    ) async throws -> [ExportResult] {
        var results: [ExportResult] = []
        for page in project.orderedPages {
            results.append(try await execute(project: project, pageIndex: page.index, format: format))
        }
        return results
    }

    /// X組写真の書き出し: 1ページ上の各配置（スロット）を個別の実解像度画像として書き出す。
    /// スロット間のガター・ページ余白は含めず、各画像はスロットの内容を縁いっぱいに描く
    /// （写真ごとの枠線は保持される）。保存順＝表示順（sortIndex順）＝X投稿順。
    public func executeSlots(
        project: ProjectEntity,
        pageIndex: Int,
        format: ExportFormat = .defaultJPEG
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
                format: format
            ))
        }
        return results
    }

    private func render(
        page: PageEntity,
        placements: [PlacementEntity],
        defaultFrame: PhotoFrameStyle,
        format: ExportFormat
    ) async throws -> ExportResult {
        let pixelSize = ExportSizeCalculator.pageSize(page: page, placements: placements)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: placements,
            defaultFrame: defaultFrame,
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
