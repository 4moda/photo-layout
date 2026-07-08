import Foundation
import Observation
import UIKit
import PhotoLayoutCore

@Observable
@MainActor
final class PageEditorViewModel {
    private(set) var project: ProjectEntity
    private(set) var previewImages: [UUID: UIImage] = [:]
    var isExporting = false
    var exportMessage: String?
    var errorMessage: String?

    // MARK: - 編集状態（ジェスチャ）

    var currentPageIndex = 0
    var selectedPlacementID: UUID?
    /// non-nil = クロップモード（ダブルタップで枠を固定し中身を動かす）
    var cropModePlacementID: UUID?
    /// スナップ発生中に表示するガイド線（配置領域の正規化座標）
    private(set) var activeGuides: [SnapEngine.Guide] = []
    /// ジェスチャ開始時点のスナップショット。累積translation/magnificationの基準
    private var gestureBase: ProjectEntity?
    /// undo/redo履歴（操作の確定単位で積む。ジェスチャ中の中間状態は積まない）
    private var history = EditHistory()

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    private let saveProject: SaveProjectUseCase
    private let addPhoto: AddPhotoUseCase
    private let exportPage: ExportPageUseCase
    private let imageProvider: any PreviewImageProviding

    init(
        project: ProjectEntity,
        saveProject: SaveProjectUseCase,
        addPhoto: AddPhotoUseCase,
        exportPage: ExportPageUseCase,
        imageProvider: any PreviewImageProviding
    ) {
        self.project = project
        self.saveProject = saveProject
        self.addPhoto = addPhoto
        self.exportPage = exportPage
        self.imageProvider = imageProvider
    }

    var page: PageEntity? { project.page(at: currentPageIndex) }
    var pagePlacements: [PlacementEntity] { project.placements(onPage: currentPageIndex) }
    var pageCount: Int { project.pages.count }
    var hasPhoto: Bool { !project.placements.isEmpty }
    var currentPageHasPhoto: Bool { !pagePlacements.isEmpty }

    func onAppear() async {
        await refreshImages()
    }

    // MARK: - ページ切替

    func goToPage(_ index: Int) {
        guard project.page(at: index) != nil else { return }
        currentPageIndex = index
        selectedPlacementID = nil
        cropModePlacementID = nil
        activeGuides = []
    }

    /// 選択状態を保ったまま「現在ページ」だけ移す（シームレスキャンバスのパン/タップ用）
    func focusPage(_ index: Int) {
        guard project.page(at: index) != nil else { return }
        currentPageIndex = index
    }

    /// ページ追加（自由レイアウト/Instagram複数ページ用。アスペクトは最終ページを引き継ぐ）
    func addPage() async {
        record()
        project.appendPage()
        currentPageIndex = pageCount - 1
        await persist(refreshImages: false)
    }

    /// 現在ページを削除（最後の1ページは不可）
    func deleteCurrentPage() async {
        guard pageCount > 1 else { return }
        record()
        project.removePage(at: currentPageIndex)
        currentPageIndex = min(currentPageIndex, pageCount - 1)
        selectedPlacementID = nil
        cropModePlacementID = nil
        await persist()
    }

    // MARK: - 写真・スタイル

    func addPhotoData(_ data: Data) async {
        do {
            record()
            project = try await addPhoto.execute(
                project: project, imageData: data, pageIndex: currentPageIndex
            )
            await refreshImages()
        } catch {
            errorMessage = "写真を読み込めませんでした: \(error.localizedDescription)"
        }
    }

    func setAspect(_ aspect: AspectRatio) async {
        record()
        project.setPageAspect(aspect)
        await persist()
    }

    /// 全面配置（ワンタップ配置アクション。永続モードではない）
    func placeFill() async {
        record()
        project.placeAllFillingPage()
        await persist()
    }

    /// マット配置（写真全体を余白付きで見せる）
    func placeMat() async {
        record()
        project.placeAllMatted()
        await persist()
    }

    func applyPreset(_ preset: FramePreset) async {
        record()
        project.applyFramePreset(preset)
        await persist()
    }

    // MARK: - 選択中の写真への操作（写真メニュー）

    func deleteSelectedPhoto() async {
        guard let id = selectedPlacementID else { return }
        record()
        project.removePlacement(id: id)
        selectedPlacementID = nil
        cropModePlacementID = nil
        await persist()
    }

    func placeFillSelected() async {
        guard let id = selectedPlacementID else { return }
        record()
        project.placeFillingPage(placementID: id)
        await persist(refreshImages: false)
    }

    func placeMatSelected() async {
        guard let id = selectedPlacementID else { return }
        record()
        project.placeMatted(placementID: id)
        await persist(refreshImages: false)
    }

    // MARK: - ジェスチャ（PlacementGesture/SnapEngineの純粋計算をproject状態へ適用する）

    /// 指定点（配置領域の正規化座標）にある最前面の配置を返す
    func placement(atNormalizedX x: Double, y: Double, onPage pageIndex: Int? = nil) -> PlacementEntity? {
        project.placements(onPage: pageIndex ?? currentPageIndex).last { placement in
            placement.destRect.minX <= x && x <= placement.destRect.maxX
                && placement.destRect.minY <= y && y <= placement.destRect.maxY
        }
    }

    func select(_ placementID: UUID?) {
        selectedPlacementID = placementID
        if cropModePlacementID != placementID {
            cropModePlacementID = nil
        }
    }

    /// ダブルタップ: クロップモードの入/切
    func toggleCropMode(_ placementID: UUID) {
        selectedPlacementID = placementID
        cropModePlacementID = (cropModePlacementID == placementID) ? nil : placementID
    }

    /// クロップ完了（枠外タップ）。選択は維持する
    func exitCropMode() {
        cropModePlacementID = nil
    }

    /// ドラッグ移動（通常モード）。translationは配置領域の正規化座標の累積移動量
    func updateMove(placementID: UUID, translationX: Double, translationY: Double) {
        guard let base = basePlacement(placementID) else { return }
        let others = (gestureBase ?? project).placements(onPage: currentPageIndex)
            .filter { $0.id != placementID }
            .map(\.destRect)
        let result = PlacementGesture.move(
            destRect: base.destRect,
            translationX: translationX,
            translationY: translationY,
            others: others
        )
        setDestRect(result.rect, for: placementID)
        activeGuides = result.guides
    }

    /// ピンチ拡縮（通常モード・アスペクト固定・中心固定）。factorはジェスチャ開始からの累積倍率
    func updateScale(placementID: UUID, factor: Double) {
        guard let base = basePlacement(placementID) else { return }
        setDestRect(PlacementGesture.scale(destRect: base.destRect, factor: factor), for: placementID)
    }

    /// 角ハンドル拡縮: 触っていない対角（anchor）を固定してアスペクト固定拡縮
    func updateScaleAnchored(placementID: UUID, factor: Double, anchor: PlacementGesture.Corner) {
        guard let base = basePlacement(placementID) else { return }
        setDestRect(
            PlacementGesture.scaleAnchored(destRect: base.destRect, factor: factor, anchor: anchor),
            for: placementID
        )
    }

    /// 辺ハンドル: 枠のアスペクトを変える（画像は歪まずクロップ窓が変わる）
    func updateStretchEdge(placementID: UUID, edge: PlacementGesture.Edge, delta: Double) {
        guard let base = basePlacement(placementID) else { return }
        let rect = PlacementGesture.stretchEdge(destRect: base.destRect, edge: edge, delta: delta)
        project.resizeFrame(placementID: placementID, to: rect, recroppingFrom: base.cropRect)
    }

    /// 枠のpxアスペクトをプリセット値へ変更（写真メニュー）
    func applyFrameAspect(pixelAspect: Double) async {
        guard let id = selectedPlacementID else { return }
        record()
        project.setFramePixelAspect(pixelAspect, placementID: id)
        await persist(refreshImages: false)
    }

    /// 枠を元画像のアスペクトに合わせる（クロップなしの全体表示になる）
    func applyPhotoNativeAspect() async {
        guard let id = selectedPlacementID,
              let placement = project.placements.first(where: { $0.id == id }) else { return }
        await applyFrameAspect(pixelAspect: placement.photo.aspectRatio.ratio)
    }

    /// クロップモードのパン。translationは枠（destRect）に対する正規化移動量
    func updateCropPan(placementID: UUID, translationX: Double, translationY: Double) {
        guard let base = basePlacement(placementID) else { return }
        setCropRect(
            PlacementGesture.panCrop(
                cropRect: base.cropRect, translationX: translationX, translationY: translationY
            ),
            for: placementID
        )
    }

    /// クロップモードのズーム。factor > 1 で拡大
    func updateCropZoom(placementID: UUID, factor: Double) {
        guard let base = basePlacement(placementID) else { return }
        setCropRect(PlacementGesture.zoomCrop(cropRect: base.cropRect, factor: factor), for: placementID)
    }

    /// ジェスチャ終了: ガイドを消して永続化（画像は不変なので再デコードしない）。
    /// 変更があった場合のみジェスチャ開始時点の状態をundo履歴へ積む
    func endGesture() async {
        if let base = gestureBase, base != project {
            history.push(base)
        }
        gestureBase = nil
        activeGuides = []
        await persist(refreshImages: false)
    }

    private func basePlacement(_ placementID: UUID) -> PlacementEntity? {
        if gestureBase == nil { gestureBase = project }
        return gestureBase?.placements.first { $0.id == placementID }
    }

    private func setDestRect(_ rect: LayoutRect, for placementID: UUID) {
        guard let index = project.placements.firstIndex(where: { $0.id == placementID }) else { return }
        project.placements[index].destRect = rect
    }

    private func setCropRect(_ rect: LayoutRect, for placementID: UUID) {
        guard let index = project.placements.firstIndex(where: { $0.id == placementID }) else { return }
        project.placements[index].cropRect = rect
    }

    // MARK: - Undo/Redo

    /// 操作の確定直前に呼ぶ（この後projectを変更する）
    private func record() {
        history.push(project)
    }

    func undo() async {
        guard let previous = history.undo(current: project) else { return }
        project = previous
        selectedPlacementID = nil
        cropModePlacementID = nil
        activeGuides = []
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
        await persist()
    }

    func redo() async {
        guard let next = history.redo(current: project) else { return }
        project = next
        selectedPlacementID = nil
        cropModePlacementID = nil
        activeGuides = []
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
        await persist()
    }

    // MARK: - 書き出し

    func export() async {
        guard hasPhoto else {
            exportMessage = "写真を追加してください"
            return
        }
        if project.isXPost {
            let emptyPages = project.orderedPages.filter { project.placements(onPage: $0.index).isEmpty }
            guard emptyPages.isEmpty else {
                exportMessage = "空のスロットがあります。すべてのスロットに写真を追加してください"
                return
            }
        }
        isExporting = true
        defer { isExporting = false }
        do {
            if pageCount > 1 {
                let results = try await exportPage.executeAll(project: project)
                let totalMB = Double(results.reduce(0) { $0 + $1.byteCount }) / 1_000_000
                exportMessage = String(
                    format: "%d枚を投稿順に書き出しました（計%.1fMB）\nカメラロールに保存済み",
                    results.count, totalMB
                )
            } else {
                let result = try await exportPage.execute(project: project, pageIndex: currentPageIndex)
                let mb = Double(result.byteCount) / 1_000_000
                exportMessage = String(
                    format: "書き出し完了: %.0f×%.0fpx / %.1fMB\nカメラロールに保存しました",
                    result.pixelSize.width, result.pixelSize.height, mb
                )
            }
        } catch {
            exportMessage = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    private func persist(refreshImages: Bool = true) async {
        do {
            project = try await saveProject.execute(project)
        } catch {
            errorMessage = error.localizedDescription
        }
        if refreshImages {
            await self.refreshImages()
        }
    }

    private func refreshImages() async {
        previewImages = await imageProvider.previewImages(project: project)
    }
}
