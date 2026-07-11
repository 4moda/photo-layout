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
    /// 写真もテンプレート（スロット）も無い"まっさら"なページか（中央の＋を出す判定）
    var currentPageIsBlank: Bool { pagePlacements.isEmpty && (page?.slots == nil) }
    /// 現在ページの写真（前面が先＝重なり順の上から）
    var currentPagePlacementsFrontFirst: [PlacementEntity] {
        Array(project.placements(onPage: currentPageIndex).reversed())
    }

    func onAppear() async {
        await refreshImages()
    }

    // MARK: - ページ切替

    /// 選択状態を保ったまま「現在ページ」だけ移す（シームレスキャンバスのパン/タップ用）
    func focusPage(_ index: Int) {
        guard project.page(at: index) != nil else { return }
        currentPageIndex = index
    }

    // MARK: - ページ俯瞰モード（挿入・削除・並べ替え。確定までは保存しない）

    var isOverviewMode = false
    /// 俯瞰モード開始時点の状態（キャンセル復帰用）
    private var overviewBase: ProjectEntity?

    func enterOverview() {
        guard !isOverviewMode else { return }
        overviewBase = project
        isOverviewMode = true
        selectedPlacementID = nil
        cropModePlacementID = nil
        activeGuides = []
    }

    /// 左上キャンセル: 俯瞰モード開始時点の状態へ復帰
    func cancelOverview() {
        if let base = overviewBase {
            project = base
        }
        overviewBase = nil
        isOverviewMode = false
    }

    /// 右上完了: 変更があればundo履歴に積んで保存
    func confirmOverview() async {
        if let base = overviewBase, base != project {
            history.push(base)
            await persist()
        }
        overviewBase = nil
        isOverviewMode = false
        currentPageIndex = min(currentPageIndex, max(pageCount - 1, 0))
    }

    func overviewInsertPage(at index: Int) {
        project.insertPage(at: index)
    }

    /// スライドを複製して直後に挿入（俯瞰の長押しメニュー用）。
    /// 複製された配置は新IDなのでプレビュー画像を再生成する（複製先にも画像が出るように）。
    func overviewDuplicatePage(at index: Int) async {
        project.duplicatePage(at: index)
        await refreshImages()
    }

    /// 俯瞰でのプロジェクト全体の背景色変更（暫定・確定は完了時）
    func overviewSetBackgroundColor(_ color: LayoutColor) {
        project.setAllPagesBackgroundColor(color)
    }

    func overviewDeletePage(at index: Int) {
        guard pageCount > 1 else { return }
        project.removePage(at: index)
    }

    /// 横並び俯瞰の「左へ/右へ」ボタン用。ページを1つ隣へ動かす。
    func overviewMovePage(from: Int, to: Int) {
        guard from != to, (0..<pageCount).contains(from), (0..<pageCount).contains(to) else { return }
        project.movePage(from: from, to: to)
    }

    /// 俯瞰でのカルーセル全体の比率変更（暫定・確定は完了時。即保存しない）
    func overviewSetAspect(_ aspect: AspectRatio) {
        project.setPageAspect(aspect)
    }

    // MARK: - 写真・スタイル

    func addPhotoData(_ data: Data) async {
        await addPhotosData([data])
    }

    /// 複数の写真データを一括で現在ページへ追加する（ピッカーの複数選択に対応）。
    /// undoは1操作にまとめる。各写真は全面配置で重なるので、必要ならこの後テンプレートで並べる。
    func addPhotosData(_ dataList: [Data]) async {
        guard !dataList.isEmpty else { return }
        record()
        do {
            for data in dataList {
                project = try await addPhoto.execute(
                    project: project, imageData: data, pageIndex: currentPageIndex
                )
            }
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

    /// スロット先行UIで選べる型枠一覧（写真の有無に依存しない）
    var availableTemplates: [LayoutTemplate] { LayoutTemplateTable.selectable }

    /// テンプレートを現在ページへ敷く（空スロットができ、後から写真を当てはめる）
    func applyTemplate(_ template: LayoutTemplate) async {
        record()
        project.applyTemplate(template, toPage: currentPageIndex)
        await persist(refreshImages: false)
    }

    /// 指定点（配置領域の正規化座標）にある空スロットのindex（無ければnil）
    func emptySlot(atNormalizedX x: Double, y: Double, onPage pageIndex: Int) -> Int? {
        guard let slots = project.page(at: pageIndex)?.slots else { return nil }
        let empties = Set(project.emptySlotIndices(onPage: pageIndex))
        for (i, slot) in slots.enumerated() where empties.contains(i) {
            if slot.minX <= x, x <= slot.maxX, slot.minY <= y, y <= slot.maxY { return i }
        }
        return nil
    }

    /// 空スロットへ写真を1枚当てはめる（スロット先行UI）
    func assignPhotoToSlot(pageIndex: Int, slotIndex: Int, data: Data) async {
        record()
        do {
            project = try await addPhoto.executeAssignToSlot(
                project: project, imageData: data, pageIndex: pageIndex, slot: slotIndex
            )
            await refreshImages()
        } catch {
            errorMessage = "写真を読み込めませんでした: \(error.localizedDescription)"
        }
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

    // MARK: - ジェスチャ（PlacementGesture/SnapEngineの純粋計算をproject状態へ適用する）

    /// 指定点（配置領域の正規化座標）にある最前面の配置を返す。
    /// 隣からはみ出して重なる写真も対象にする（プロジェクト配置モデル。座標は対象ページローカル）。
    func placement(atNormalizedX x: Double, y: Double, onPage pageIndex: Int? = nil) -> PlacementEntity? {
        let page = pageIndex ?? currentPageIndex
        return SpreadGeometry.visiblePlacements(onPage: page, project: project).last { placement in
            placement.destRect.minX <= x && x <= placement.destRect.maxX
                && placement.destRect.minY <= y && y <= placement.destRect.maxY
        }
    }

    func select(_ placementID: UUID?) {
        selectedPlacementID = placementID
        // 選択した写真の所属スライドを現在ページにする（選択枠・四隅ハンドルが必ず画面内に出るように）
        if let id = placementID, let p = project.placements.first(where: { $0.id == id }) {
            currentPageIndex = p.pageIndex
        }
        if cropModePlacementID != placementID {
            cropModePlacementID = nil
        }
    }

    /// 選択解除（写真の選択を外す＝スライド編集コンテキストへ戻る）
    func deselectAll() {
        selectedPlacementID = nil
        cropModePlacementID = nil
        activeGuides = []
    }

    // MARK: - スライドのスタイル・レイヤー（スライド編集コンテキスト）

    /// 選択中の写真の枠（縁）を設定（写真選択コンテキスト）
    func setSelectedPhotoFrame(_ frame: PhotoFrameStyle?) async {
        guard let id = selectedPlacementID else { return }
        record()
        project.setPlacementFrame(frame, placementID: id)
        await persist(refreshImages: false)
    }

    /// レイヤー順序: 指定写真を1段前面/背面へ（ページ選択のレイヤーリスト用）
    func bringForward(placementID: UUID) async {
        record()
        project.bringForward(placementID: placementID)
        await persist(refreshImages: false)
    }

    func sendBackward(placementID: UUID) async {
        record()
        project.sendBackward(placementID: placementID)
        await persist(refreshImages: false)
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

    /// 角ハンドル拡縮: 触っていない対角（anchor）を固定してアスペクト固定拡縮。
    /// 移動時と同様にページ端・中心へスナップし、ガイド線を表示する。
    func updateScaleAnchored(placementID: UUID, factor: Double, anchor: PlacementGesture.Corner) {
        guard let base = basePlacement(placementID) else { return }
        let result = PlacementGesture.scaleAnchoredSnapped(
            destRect: base.destRect, factor: factor, anchor: anchor
        )
        setDestRect(result.rect, for: placementID)
        activeGuides = result.guides
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

    /// ページを1枚の画像として書き出す（複数ページなら各ページを投稿順に）。合成レイアウトの基本。
    func exportPages() async {
        guard hasPhoto else {
            exportMessage = "写真を追加してください"
            return
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
