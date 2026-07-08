import SwiftUI
import PhotosUI
import PhotoLayoutCore

/// ページ編集画面。プロジェクト種別で編集面が変わる:
/// - X投稿: タイムライン合成ビュー（Issue #15 でテンプレートへ統合予定）
/// - Instagram/自由: シームレスキャンバス — 全ページを隙間ゼロで横に連結し、
///   パンで移動・写真非選択時のピンチでビューポートをズームする（Issue #9）。
///   写真操作は ドラッグ=移動（スナップ）、ピンチ/角ハンドル=アスペクト固定拡縮、
///   ダブルタップ=クロップモード（枠外タップで完了）
struct PageEditorView: View {
    @State private var viewModel: PageEditorViewModel
    @State private var photoPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?
    /// 角ハンドルドラッグ開始時の角と中心（拡縮中に選択枠が動いても基準がぶれないよう固定）
    @State private var handleDragBase: (corner: CGPoint, center: CGPoint)?

    // シームレスキャンバスのビューポート状態
    @State private var viewZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var pinchBase: (zoom: CGFloat, pan: CGSize)?
    @State private var dragMode: SpreadDragMode?
    @State private var didInitialScroll = false

    private enum SpreadDragMode {
        case photo(id: UUID, isCrop: Bool, denom: CGSize)
        case pan(base: CGSize)
        case suppressed // 角ハンドル付近から始まったドラッグはハンドル側に譲る
    }

    init(viewModel: PageEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private static let aspectChoices: [(label: String, aspect: AspectRatio)] = [
        ("3:4 縦 (X 1枚)", AspectRatio(width: 3, height: 4)),
        ("4:5 縦 (Instagram)", AspectRatio(width: 4, height: 5)),
        ("1:1", AspectRatio(width: 1, height: 1)),
        ("1.91:1 横 (Instagram)", AspectRatio(width: 1.91, height: 1)),
        ("16:9 横", AspectRatio(width: 16, height: 9))
    ]

    private static let presetChoices: [(label: String, preset: FramePreset)] = [
        ("余白なし", .none),
        ("白余白", .whiteMargin),
        ("黒フチ細", .thinBlackBorder),
        ("白余白＋黒フチ", .whiteMarginBlackBorder),
        ("黒背景＋白フチ", .blackBackgroundWhiteBorder)
    ]

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.project.isXPost {
                xComposite
                    .padding(.horizontal)
                    .frame(maxHeight: .infinity)
                Text("スロットをタップして写真を追加 — ドラッグ/ピンチで見える範囲を調整")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                spreadCanvas
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("pageEditor.canvas")

                if viewModel.cropModePlacementID != nil {
                    Text("クロップ調整中 — ドラッグ/ピンチで位置と拡大を変更、枠の外をタップで完了")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("pageEditor.cropModeHint")
                }

            }

            controls
        }
        .padding(.vertical)
        .navigationTitle(viewModel.project.title ?? "レイアウト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.project.isXPost {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        photoPickerPresented = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    .accessibilityIdentifier("pageEditor.addPhoto")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.export() }
                } label: {
                    if viewModel.isExporting {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .disabled(viewModel.isExporting || !viewModel.hasPhoto)
                .accessibilityIdentifier("pageEditor.export")
            }
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.addPhotoData(data)
                }
                pickerItem = nil
            }
        }
        .task { await viewModel.onAppear() }
        .alert("書き出し", isPresented: .init(
            get: { viewModel.exportMessage != nil },
            set: { if !$0 { viewModel.exportMessage = nil } }
        )) {
            Button("OK") { viewModel.exportMessage = nil }
        } message: {
            Text(viewModel.exportMessage ?? "")
        }
    }

    // MARK: - シームレスキャンバス（スプレッド表示）

    /// 全ページを SpreadGeometry の座標で隙間なく連結して描画する。
    /// パン=ドラッグ（空き地から開始）、ズーム=写真非選択時のピンチ。
    private var spreadCanvas: some View {
        GeometryReader { geo in
            let project = viewModel.project
            let stripHeight = geo.size.height * viewZoom
            let stripWidth = CGFloat(SpreadGeometry.totalWidth(project: project)) * stripHeight

            ZStack(alignment: .topLeading) {
                ForEach(project.orderedPages, id: \.id) { page in
                    if let frame = SpreadGeometry.pageFrame(project: project, pageIndex: page.index) {
                        CanvasRenderView(
                            page: page,
                            placements: project.placements(onPage: page.index),
                            defaultFrame: project.defaultPhotoFrame,
                            images: viewModel.previewImages
                        )
                        .frame(width: frame.width * stripHeight, height: stripHeight)
                        .position(
                            x: (frame.x + frame.width / 2) * stripHeight,
                            y: stripHeight / 2
                        )
                    }
                }
                // ページ境界の目印（書き出しには含まれない）
                ForEach(Array(project.orderedPages.dropFirst()), id: \.id) { page in
                    if let originX = SpreadGeometry.pageOriginX(project: project, pageIndex: page.index) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 1, height: stripHeight)
                            .position(x: CGFloat(originX) * stripHeight, y: stripHeight / 2)
                            .allowsHitTesting(false)
                    }
                }
                stripSelectionOverlay(stripHeight: stripHeight)
            }
            .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
            .offset(panOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(stripDoubleTap(geo: geo).exclusively(before: stripSingleTap(geo: geo)))
            .simultaneousGesture(stripDrag(geo: geo))
            .simultaneousGesture(stripMagnify(geo: geo))
            .onAppear {
                if !didInitialScroll {
                    didInitialScroll = true
                    panOffset = clampedPan(desired: initialPan(geo: geo), geo: geo)
                }
            }
            // ページ追加/削除後は現在ページへスクロールを合わせる
            .onChange(of: viewModel.pageCount) { _, _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    panOffset = clampedPan(desired: initialPan(geo: geo), geo: geo)
                }
            }
        }
    }

    /// 選択中の配置の枠・角ハンドル・スナップガイド（スプレッド座標）
    @ViewBuilder
    private func stripSelectionOverlay(stripHeight: CGFloat) -> some View {
        if let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
           let selectedID = viewModel.selectedPlacementID,
           let placement = viewModel.project.placements.first(where: { $0.id == selectedID }) {
            let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
            selectionChrome(
                rect: rect,
                isCrop: viewModel.cropModePlacementID == selectedID,
                placementID: selectedID
            )
            ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { _, guide in
                guideLine(guide, contentRect: contentStrip)
            }
        }
    }

    /// 選択中の配置が属するページの配置領域（スプレッド空間のpt矩形）
    private func selectedContentRectInStrip(stripHeight: CGFloat) -> LayoutRect? {
        guard let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID }),
              let page = viewModel.project.page(at: placement.pageIndex),
              let originX = SpreadGeometry.pageOriginX(project: viewModel.project, pageIndex: placement.pageIndex)
        else { return nil }
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        return LayoutRect(
            x: content.x + originX * stripHeight,
            y: content.y,
            width: content.width,
            height: content.height
        )
    }

    // MARK: - キャンバス座標変換

    /// 画面点 →（ページindex, 配置領域の正規化座標）
    private func locate(_ point: CGPoint, geo: GeometryProxy) -> (pageIndex: Int, nx: Double, ny: Double)? {
        let stripHeight = geo.size.height * viewZoom
        let sp = CGPoint(x: point.x - panOffset.width, y: point.y - panOffset.height)
        guard sp.y >= 0, sp.y <= stripHeight else { return nil }
        let spreadX = Double(sp.x / stripHeight)
        guard let pageIndex = SpreadGeometry.pageIndex(atSpreadX: spreadX, project: viewModel.project),
              let page = viewModel.project.page(at: pageIndex),
              let originX = SpreadGeometry.pageOriginX(project: viewModel.project, pageIndex: pageIndex)
        else { return nil }
        let pagePt = CGPoint(x: sp.x - CGFloat(originX) * stripHeight, y: sp.y)
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        guard content.width > 0, content.height > 0 else { return nil }
        return (
            pageIndex,
            (Double(pagePt.x) - content.x) / content.width,
            (Double(pagePt.y) - content.y) / content.height
        )
    }

    private func initialPan(geo: GeometryProxy) -> CGSize {
        let stripHeight = geo.size.height * viewZoom
        let originX = SpreadGeometry.pageOriginX(
            project: viewModel.project, pageIndex: viewModel.currentPageIndex
        ) ?? 0
        return CGSize(width: -CGFloat(originX) * stripHeight, height: 0)
    }

    /// パンの可動域: キャンバスがビューポートより小さい軸は中央固定、大きい軸は端まで
    private func clampedPan(desired: CGSize, geo: GeometryProxy, zoom: CGFloat? = nil) -> CGSize {
        let z = zoom ?? viewZoom
        let stripHeight = geo.size.height * z
        let stripWidth = CGFloat(SpreadGeometry.totalWidth(project: viewModel.project)) * stripHeight
        var x = desired.width
        var y = desired.height
        if stripWidth <= geo.size.width {
            x = (geo.size.width - stripWidth) / 2
        } else {
            x = min(max(x, geo.size.width - stripWidth), 0)
        }
        if stripHeight <= geo.size.height {
            y = (geo.size.height - stripHeight) / 2
        } else {
            y = min(max(y, geo.size.height - stripHeight), 0)
        }
        return CGSize(width: x, height: y)
    }

    // MARK: - キャンバスのジェスチャ

    private func stripSingleTap(geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let loc = locate(value.location, geo: geo) else {
                if viewModel.cropModePlacementID != nil {
                    viewModel.exitCropMode()
                } else {
                    viewModel.select(nil)
                }
                return
            }
            viewModel.focusPage(loc.pageIndex)
            let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex)
            if let cropID = viewModel.cropModePlacementID {
                if hit?.id != cropID {
                    viewModel.exitCropMode()
                }
            } else {
                viewModel.select(hit?.id)
            }
        }
    }

    private func stripDoubleTap(geo: GeometryProxy) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
            guard let loc = locate(value.location, geo: geo),
                  let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex)
            else { return }
            viewModel.focusPage(loc.pageIndex)
            viewModel.toggleCropMode(hit.id)
        }
    }

    /// 写真の上から開始=写真の移動（クロップ中はクロップパン）、それ以外=ビューポートのパン
    private func stripDrag(geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = beginStripDrag(at: value.startLocation, geo: geo)
                }
                switch dragMode {
                case .photo(let id, let isCrop, let denom):
                    if isCrop {
                        viewModel.updateCropPan(
                            placementID: id,
                            translationX: value.translation.width / denom.width,
                            translationY: value.translation.height / denom.height
                        )
                    } else {
                        viewModel.updateMove(
                            placementID: id,
                            translationX: value.translation.width / denom.width,
                            translationY: value.translation.height / denom.height
                        )
                    }
                case .pan(let base):
                    panOffset = clampedPan(
                        desired: CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height
                        ),
                        geo: geo
                    )
                case .suppressed, nil:
                    break
                }
            }
            .onEnded { _ in
                if case .photo = dragMode {
                    Task { await viewModel.endGesture() }
                }
                if case .pan = dragMode {
                    focusCenterPage(geo: geo)
                }
                dragMode = nil
            }
    }

    private func beginStripDrag(at start: CGPoint, geo: GeometryProxy) -> SpreadDragMode {
        // 角ハンドル付近はハンドルのジェスチャに譲る
        if let corners = selectedCornersInViewport(geo: geo),
           corners.contains(where: { hypot($0.x - start.x, $0.y - start.y) < 24 }) {
            return .suppressed
        }
        guard let loc = locate(start, geo: geo),
              let hit = viewModel.placement(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex),
              let page = viewModel.project.page(at: loc.pageIndex)
        else {
            return .pan(base: panOffset)
        }
        viewModel.focusPage(loc.pageIndex)
        let stripHeight = geo.size.height * viewZoom
        let pageSize = LayoutSize(width: page.aspect.ratio * stripHeight, height: stripHeight)
        let content = PageGeometry.contentRect(page: page, pageSize: pageSize)
        let isCrop = viewModel.cropModePlacementID == hit.id
        if isCrop {
            let imageRect = PageGeometry.imageRect(destRect: hit.destRect, in: content)
            return .photo(id: hit.id, isCrop: true, denom: CGSize(width: imageRect.width, height: imageRect.height))
        }
        viewModel.select(hit.id)
        return .photo(id: hit.id, isCrop: false, denom: CGSize(width: content.width, height: content.height))
    }

    /// 選択中配置の角ハンドルのビューポート座標（ドラッグの競合判定用）
    private func selectedCornersInViewport(geo: GeometryProxy) -> [CGPoint]? {
        let stripHeight = geo.size.height * viewZoom
        guard viewModel.cropModePlacementID == nil,
              let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
              let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID })
        else { return nil }
        let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ].map { CGPoint(x: $0.x + panOffset.width, y: $0.y + panOffset.height) }
    }

    /// ピンチ: 写真選択中=写真の拡縮（クロップ中=クロップズーム）/ 非選択=ビューポートズーム
    private func stripMagnify(geo: GeometryProxy) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if let targetID = viewModel.cropModePlacementID ?? viewModel.selectedPlacementID {
                    if viewModel.cropModePlacementID == targetID {
                        viewModel.updateCropZoom(placementID: targetID, factor: value.magnification)
                    } else {
                        viewModel.updateScale(placementID: targetID, factor: value.magnification)
                    }
                } else {
                    if pinchBase == nil {
                        pinchBase = (zoom: viewZoom, pan: panOffset)
                    }
                    guard let base = pinchBase else { return }
                    let newZoom = min(max(base.zoom * value.magnification, 0.25), 4)
                    // ビューポート中央を不動点にする
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let ratio = newZoom / base.zoom
                    let newPan = CGSize(
                        width: center.x - (center.x - base.pan.width) * ratio,
                        height: center.y - (center.y - base.pan.height) * ratio
                    )
                    viewZoom = newZoom
                    panOffset = clampedPan(desired: newPan, geo: geo, zoom: newZoom)
                }
            }
            .onEnded { _ in
                if pinchBase == nil {
                    Task { await viewModel.endGesture() }
                } else {
                    pinchBase = nil
                    focusCenterPage(geo: geo)
                }
            }
    }

    /// ビューポート中央にあるページを「現在ページ」にする
    private func focusCenterPage(geo: GeometryProxy) {
        let stripHeight = geo.size.height * viewZoom
        guard stripHeight > 0 else { return }
        let spreadX = Double((geo.size.width / 2 - panOffset.width) / stripHeight)
        if let index = SpreadGeometry.pageIndex(atSpreadX: spreadX, project: viewModel.project) {
            viewModel.focusPage(index)
        }
    }

    // MARK: - Xタイムライン合成ビュー

    /// 全ページをXタイムラインの並び（左右/左大＋右2段/田の字）で1画面に展開する。
    /// スロット内のドラッグ/ピンチはそのページの写真のクロップ調整（枠は固定）。
    private var xComposite: some View {
        let count = viewModel.pageCount
        let aspect = XTimelineComposite.canvasAspect(photoCount: count)
        let slots = XTimelineComposite.slots(photoCount: count)
        return GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(viewModel.project.orderedPages, id: \.id) { page in
                    if page.index < slots.count {
                        let rect = slotDisplayRect(
                            slot: slots[page.index], pageAspect: page.aspect, canvasSize: geo.size
                        )
                        slotView(page: page, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
        .aspectRatio(aspect.ratio, contentMode: .fit)
        .accessibilityIdentifier("pageEditor.xComposite")
    }

    /// スロット矩形（正規化）→表示pt矩形。ページの正確なアスペクトに内接させる
    private func slotDisplayRect(slot: LayoutRect, pageAspect: AspectRatio, canvasSize: CGSize) -> CGRect {
        let raw = LayoutRect(
            x: slot.x * canvasSize.width,
            y: slot.y * canvasSize.height,
            width: slot.width * canvasSize.width,
            height: slot.height * canvasSize.height
        )
        let fitted = raw.fitting(pageAspect)
        return CGRect(x: fitted.x, y: fitted.y, width: fitted.width, height: fitted.height)
    }

    @ViewBuilder
    private func slotView(page: PageEntity, size: CGSize) -> some View {
        let placements = viewModel.project.placements(onPage: page.index)
        let isSelected = viewModel.currentPageIndex == page.index
        if let placement = placements.first {
            CanvasRenderView(
                page: page,
                placements: placements,
                defaultFrame: viewModel.project.defaultPhotoFrame,
                images: viewModel.previewImages
            )
            .overlay {
                if isSelected {
                    Rectangle().stroke(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.goToPage(page.index) }
            .gesture(slotCropDragGesture(placementID: placement.id, pageIndex: page.index, slotSize: size))
            .simultaneousGesture(slotCropZoomGesture(placementID: placement.id, pageIndex: page.index))
            .accessibilityIdentifier("pageEditor.slot\(page.index)")
        } else {
            Button {
                viewModel.goToPage(page.index)
                photoPickerPresented = true
            } label: {
                ZStack {
                    Rectangle().fill(Color(.systemGray5))
                    Image(systemName: "plus")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pageEditor.emptySlot\(page.index)")
        }
    }

    private func slotCropDragGesture(placementID: UUID, pageIndex: Int, slotSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                viewModel.goToPage(pageIndex)
                // スロット（＝枠）サイズに対する相対移動量
                viewModel.updateCropPan(
                    placementID: placementID,
                    translationX: value.translation.width / max(slotSize.width, 1),
                    translationY: value.translation.height / max(slotSize.height, 1)
                )
            }
            .onEnded { _ in
                Task { await viewModel.endGesture() }
            }
    }

    private func slotCropZoomGesture(placementID: UUID, pageIndex: Int) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                viewModel.goToPage(pageIndex)
                viewModel.updateCropZoom(placementID: placementID, factor: value.magnification)
            }
            .onEnded { _ in
                Task { await viewModel.endGesture() }
            }
    }

    // MARK: - 選択枠・ハンドル・ガイド（共通部品）

    /// 選択枠＋四隅の拡縮ハンドル（角ドラッグ＝アスペクト固定拡縮）
    @ViewBuilder
    private func selectionChrome(rect: LayoutRect, isCrop: Bool, placementID: UUID) -> some View {
        let color: Color = isCrop ? .orange : .accentColor
        Rectangle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: isCrop ? [6, 4] : []))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
        if !isCrop {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY)
            ]
            ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
                ZStack {
                    Circle().fill(Color.white)
                    Circle().stroke(color, lineWidth: 2)
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle().scale(2)) // 指で掴みやすいよう当たり判定を広げる
                .position(corner)
                .gesture(cornerHandleGesture(placementID: placementID, corner: corner, center: center))
            }
        }
    }

    /// 角ハンドルのドラッグ: 中心からの距離比＝拡縮率（アスペクト固定）。
    /// 拡縮でハンドル位置自体が動くため、基準の角・中心はドラッグ開始時の値に固定する
    private func cornerHandleGesture(placementID: UUID, corner: CGPoint, center: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if handleDragBase == nil {
                    handleDragBase = (corner: corner, center: center)
                }
                guard let base = handleDragBase else { return }
                let baseDistance = hypot(base.corner.x - base.center.x, base.corner.y - base.center.y)
                guard baseDistance > 1 else { return }
                let current = CGPoint(
                    x: base.corner.x + value.translation.width,
                    y: base.corner.y + value.translation.height
                )
                let distance = hypot(current.x - base.center.x, current.y - base.center.y)
                viewModel.updateScale(placementID: placementID, factor: distance / baseDistance)
            }
            .onEnded { _ in
                handleDragBase = nil
                Task { await viewModel.endGesture() }
            }
    }

    private func guideLine(_ guide: SnapEngine.Guide, contentRect: LayoutRect) -> some View {
        Path { path in
            switch guide.axis {
            case .vertical:
                let x = contentRect.x + guide.position * contentRect.width
                path.move(to: CGPoint(x: x, y: contentRect.minY))
                path.addLine(to: CGPoint(x: x, y: contentRect.maxY))
            case .horizontal:
                let y = contentRect.y + guide.position * contentRect.height
                path.move(to: CGPoint(x: contentRect.minX, y: y))
                path.addLine(to: CGPoint(x: contentRect.maxX, y: y))
            }
        }
        .stroke(Color.pink, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        .allowsHitTesting(false)
    }

    // MARK: - コントロール（コンテキスト依存メニュー）

    /// 選択状態に応じて出すメニューを切り替える:
    /// クロップ中=完了のみ / 写真選択中=写真メニュー / 非選択=ページ全体メニュー
    @ViewBuilder
    private var controls: some View {
        if viewModel.project.isXPost {
            xControls
        } else if viewModel.cropModePlacementID != nil {
            cropControls
        } else if viewModel.selectedPlacementID != nil {
            photoControls
        } else {
            pageMenuControls
        }
    }

    private var cropControls: some View {
        Button {
            viewModel.exitCropMode()
        } label: {
            Label("クロップ完了", systemImage: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("pageEditor.cropDone")
    }

    /// 写真選択中のメニュー
    private var photoControls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.placeFillSelected() }
            } label: {
                Label("全面", systemImage: "rectangle.arrowtriangle.2.inward")
            }
            .accessibilityIdentifier("pageEditor.fillSelected")

            Button {
                Task { await viewModel.placeMatSelected() }
            } label: {
                Label("マット", systemImage: "rectangle.arrowtriangle.2.outward")
            }
            .accessibilityIdentifier("pageEditor.matSelected")

            Button {
                if let id = viewModel.selectedPlacementID {
                    viewModel.toggleCropMode(id)
                }
            } label: {
                Label("クロップ", systemImage: "crop")
            }
            .accessibilityIdentifier("pageEditor.cropButton")

            Button(role: .destructive) {
                Task { await viewModel.deleteSelectedPhoto() }
            } label: {
                Label("削除", systemImage: "trash")
            }
            .accessibilityIdentifier("pageEditor.deletePhoto")
        }
        .buttonStyle(.bordered)
    }

    /// 非選択時のページ全体メニュー
    private var pageMenuControls: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(Self.aspectChoices, id: \.label) { choice in
                    Button(choice.label) {
                        Task { await viewModel.setAspect(choice.aspect) }
                    }
                }
            } label: {
                Label("比率", systemImage: "aspectratio")
            }
            .accessibilityIdentifier("pageEditor.aspectMenu")

            Button {
                Task { await viewModel.placeFill() }
            } label: {
                Label("全面", systemImage: "rectangle.arrowtriangle.2.inward")
            }
            .accessibilityIdentifier("pageEditor.fillButton")

            Button {
                Task { await viewModel.placeMat() }
            } label: {
                Label("マット", systemImage: "rectangle.arrowtriangle.2.outward")
            }
            .accessibilityIdentifier("pageEditor.matButton")

            framePresetMenu

            Button {
                Task { await viewModel.addPage() }
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .accessibilityIdentifier("pageEditor.addPage")

            if viewModel.pageCount > 1 {
                Button(role: .destructive) {
                    Task { await viewModel.deleteCurrentPage() }
                } label: {
                    Image(systemName: "minus.rectangle")
                }
                .accessibilityIdentifier("pageEditor.deletePage")

                Text("\(viewModel.currentPageIndex + 1)/\(viewModel.pageCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pageEditor.pageLabel")
            }
        }
        .buttonStyle(.bordered)
    }

    /// X投稿（タイムライン合成）のメニュー。比率・ページ増減はX仕様固定なので出さない
    private var xControls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.placeFill() }
            } label: {
                Label("全面", systemImage: "rectangle.arrowtriangle.2.inward")
            }
            .accessibilityIdentifier("pageEditor.fillButton")

            Button {
                Task { await viewModel.placeMat() }
            } label: {
                Label("マット", systemImage: "rectangle.arrowtriangle.2.outward")
            }
            .accessibilityIdentifier("pageEditor.matButton")

            framePresetMenu
        }
        .buttonStyle(.bordered)
    }

    private var framePresetMenu: some View {
        Menu {
            ForEach(Self.presetChoices, id: \.label) { choice in
                Button(choice.label) {
                    Task { await viewModel.applyPreset(choice.preset) }
                }
            }
        } label: {
            Label("枠", systemImage: "square.dashed")
        }
        .accessibilityIdentifier("pageEditor.presetMenu")
    }
}
