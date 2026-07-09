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
    @State private var pickerItems: [PhotosPickerItem] = []
    // スロット充填ピッカー（空スロットのタップで開く）
    @State private var slotPickerPresented = false
    @State private var slotFillItem: PhotosPickerItem?
    @State private var pendingSlotFill: (page: Int, slot: Int)?
    // カルーセル分割（1枚を全スライドへ）
    @State private var splitPickerPresented = false
    @State private var splitPickerItem: PhotosPickerItem?
    @State private var pendingSplitData: Data?
    @State private var splitCount = 3
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
            spreadCanvas
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("pageEditor.canvas")
                // 空スロット充填ピッカーはキャンバスに付ける（複数モーダルを1ノードに積まない）
                .photosPicker(isPresented: $slotPickerPresented, selection: $slotFillItem, matching: .images)
                .onChange(of: slotFillItem) { _, newItem in
                    guard let newItem, let target = pendingSlotFill else { return }
                    slotFillItem = nil
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            await viewModel.assignPhotoToSlot(
                                pageIndex: target.page, slotIndex: target.slot, data: data
                            )
                        }
                        pendingSlotFill = nil
                    }
                }

            if viewModel.cropModePlacementID != nil {
                Text("クロップ調整中 — ドラッグ/ピンチで位置と拡大を変更、枠の外をタップで完了")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("pageEditor.cropModeHint")
            }

            controls
                // 分割ピッカー＋シートはコントロール側に付ける
                .photosPicker(isPresented: $splitPickerPresented, selection: $splitPickerItem, matching: .images)
                .onChange(of: splitPickerItem) { _, newItem in
                    guard let newItem else { return }
                    splitPickerItem = nil
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self) {
                            pendingSplitData = data
                        }
                    }
                }
                .sheet(isPresented: Binding(
                    get: { pendingSplitData != nil },
                    set: { if !$0 { pendingSplitData = nil } }
                )) {
                    splitSheet
                }
        }
        .padding(.vertical)
        .navigationTitle(viewModel.project.title ?? "レイアウト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.undo() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!viewModel.canUndo)
                .accessibilityIdentifier("pageEditor.undo")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.redo() }
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!viewModel.canRedo)
                .accessibilityIdentifier("pageEditor.redo")
            }
            ToolbarItem(placement: .primaryAction) {
                // ページの追加・削除・並べ替えは俯瞰モードで（常時見える上部に置く）
                Button {
                    viewModel.enterOverview()
                } label: {
                    Image(systemName: "rectangle.stack")
                }
                .accessibilityIdentifier("pageEditor.overview")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    photoPickerPresented = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .accessibilityIdentifier("pageEditor.addPhoto")
            }
            ToolbarItem(placement: .primaryAction) {
                exportMenu
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewModel.isOverviewMode },
            set: { if !$0 { viewModel.cancelOverview() } }
        )) {
            PageOverviewView(viewModel: viewModel, thumbnailImages: viewModel.previewImages)
        }
        .photosPicker(isPresented: $photoPickerPresented, selection: $pickerItems, matching: .images)
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            pickerItems = []
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        datas.append(data)
                    }
                }
                await viewModel.addPhotosData(datas)
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
                        // 暗いキャンバス地に対してページの外周を薄く縁取り、
                        // 黒背景プリセットのページでも境界が分かるようにする
                        .overlay(Rectangle().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
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
                emptySlotOverlay(stripHeight: stripHeight)
                stripSelectionOverlay(stripHeight: stripHeight)
            }
            .frame(width: stripWidth, height: stripHeight, alignment: .topLeading)
            .offset(panOffset)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // ページ内（白）とページ外を明確に区別するため、キャンバス地を暗くする
            .background(Color(white: 0.11))
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

    /// 選択中の配置の枠・ハンドル・スナップガイド（スプレッド座標）
    @ViewBuilder
    private func stripSelectionOverlay(stripHeight: CGFloat) -> some View {
        if let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
           let selectedID = viewModel.selectedPlacementID,
           let placement = viewModel.project.placements.first(where: { $0.id == selectedID }) {
            let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
            selectionChrome(
                rect: rect,
                contentRect: contentStrip,
                isCrop: viewModel.cropModePlacementID == selectedID,
                placementID: selectedID
            )
            ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { _, guide in
                guideLine(guide, contentRect: contentStrip)
            }
        }
    }

    /// 空スロット（写真未充填）の目印＋当てはめ導線。タップは通し、visualだけ描く。
    @ViewBuilder
    private func emptySlotOverlay(stripHeight: CGFloat) -> some View {
        ForEach(viewModel.project.orderedPages, id: \.id) { page in
            if let slots = page.slots,
               let content = contentRectInStrip(pageIndex: page.index, stripHeight: stripHeight) {
                ForEach(viewModel.project.emptySlotIndices(onPage: page.index), id: \.self) { i in
                    let slot = slots[i]
                    let w = slot.width * content.width
                    let h = slot.height * content.height
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.6),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                        Image(systemName: "plus")
                            .font(.system(size: min(w, h) * 0.28))
                            .foregroundStyle(Color.white.opacity(0.8))
                    }
                    .frame(width: w, height: h)
                    .position(
                        x: content.x + (slot.x + slot.width / 2) * content.width,
                        y: content.y + (slot.y + slot.height / 2) * content.height
                    )
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// 指定ページの配置領域（スプレッド空間のpt矩形）
    private func contentRectInStrip(pageIndex: Int, stripHeight: CGFloat) -> LayoutRect? {
        guard let page = viewModel.project.page(at: pageIndex),
              let originX = SpreadGeometry.pageOriginX(project: viewModel.project, pageIndex: pageIndex)
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

    /// 選択中の配置が属するページの配置領域（スプレッド空間のpt矩形）
    private func selectedContentRectInStrip(stripHeight: CGFloat) -> LayoutRect? {
        guard let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID })
        else { return nil }
        return contentRectInStrip(pageIndex: placement.pageIndex, stripHeight: stripHeight)
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
            } else if let hit {
                viewModel.select(hit.id)
            } else if let slot = viewModel.emptySlot(atNormalizedX: loc.nx, y: loc.ny, onPage: loc.pageIndex) {
                // 空スロットのタップ → そのスロットへ当てはめる写真を選ぶ
                viewModel.select(nil)
                pendingSlotFill = (loc.pageIndex, slot)
                slotPickerPresented = true
            } else {
                viewModel.select(nil)
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

    /// 選択中配置の角・辺ハンドルのビューポート座標（キャンバスドラッグとの競合判定用）
    private func selectedCornersInViewport(geo: GeometryProxy) -> [CGPoint]? {
        let stripHeight = geo.size.height * viewZoom
        guard viewModel.cropModePlacementID == nil,
              let contentStrip = selectedContentRectInStrip(stripHeight: stripHeight),
              let selectedID = viewModel.selectedPlacementID,
              let placement = viewModel.project.placements.first(where: { $0.id == selectedID })
        else { return nil }
        let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentStrip)
        let points = Self.cornerOrder.map { cornerPoint($0, of: rect) }
            + Self.edgeOrder.map { edgePoint($0, of: rect) }
        return points.map { CGPoint(x: $0.x + panOffset.width, y: $0.y + panOffset.height) }
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
                    // 十分に引いた（縮小した）ら俯瞰モードへ。ズームは戻しておく
                    if viewZoom <= 0.55, viewModel.pageCount > 1 {
                        viewZoom = 1
                        panOffset = clampedPan(desired: initialPan(geo: geo), geo: geo)
                        viewModel.enterOverview()
                    } else {
                        focusCenterPage(geo: geo)
                    }
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

    // MARK: - 選択枠・ハンドル・ガイド（共通部品）

    /// 角の位置（ハンドル描画・アンカー計算共用）
    private func cornerPoint(_ corner: PlacementGesture.Corner, of rect: LayoutRect) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private static let cornerOrder: [PlacementGesture.Corner] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private static let edgeOrder: [PlacementGesture.Edge] = [.top, .bottom, .leading, .trailing]

    private func edgePoint(_ edge: PlacementGesture.Edge, of rect: LayoutRect) -> CGPoint {
        switch edge {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .leading: return CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    /// 選択枠＋四隅ハンドル（対角固定・アスペクト固定拡縮）＋辺ハンドル（枠アスペクト変更）
    @ViewBuilder
    private func selectionChrome(rect: LayoutRect, contentRect: LayoutRect, isCrop: Bool, placementID: UUID) -> some View {
        let color: Color = isCrop ? .orange : .accentColor
        Rectangle()
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: isCrop ? [6, 4] : []))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
        if !isCrop {
            // 角: 対角アンカーのアスペクト固定拡縮
            ForEach(Array(Self.cornerOrder.enumerated()), id: \.offset) { _, corner in
                ZStack {
                    Circle().fill(Color.white)
                    Circle().stroke(color, lineWidth: 2)
                }
                .frame(width: 16, height: 16)
                .contentShape(Circle().scale(2)) // 指で掴みやすいよう当たり判定を広げる
                .position(cornerPoint(corner, of: rect))
                .gesture(cornerHandleGesture(
                    placementID: placementID,
                    handle: cornerPoint(corner, of: rect),
                    anchor: cornerPoint(corner.opposite, of: rect)
                ))
            }
            // 辺: 枠アスペクト変更（画像は歪まずクロップ窓が変わる）
            ForEach(Array(Self.edgeOrder.enumerated()), id: \.offset) { _, edge in
                let vertical = (edge == .leading || edge == .trailing)
                ZStack {
                    Capsule().fill(Color.white)
                    Capsule().stroke(color, lineWidth: 2)
                }
                .frame(width: vertical ? 8 : 20, height: vertical ? 20 : 8)
                .contentShape(Rectangle().scale(2.5))
                .position(edgePoint(edge, of: rect))
                .gesture(edgeHandleGesture(placementID: placementID, edge: edge, contentRect: contentRect))
            }
        }
    }

    /// 角ハンドルのドラッグ: 対角（anchor）からの距離比＝拡縮率（アスペクト固定・対角固定）。
    /// 拡縮でハンドル位置自体が動くため、基準点はドラッグ開始時の値に固定する
    private func cornerHandleGesture(placementID: UUID, handle: CGPoint, anchor: CGPoint) -> some Gesture {
        let anchorCorner = anchorCorner(handle: handle, anchor: anchor)
        return DragGesture(minimumDistance: 1)
            .onChanged { value in
                if handleDragBase == nil {
                    handleDragBase = (corner: handle, center: anchor)
                }
                guard let base = handleDragBase else { return }
                let baseDistance = hypot(base.corner.x - base.center.x, base.corner.y - base.center.y)
                guard baseDistance > 1 else { return }
                let current = CGPoint(
                    x: base.corner.x + value.translation.width,
                    y: base.corner.y + value.translation.height
                )
                let distance = hypot(current.x - base.center.x, current.y - base.center.y)
                viewModel.updateScaleAnchored(
                    placementID: placementID,
                    factor: distance / baseDistance,
                    anchor: anchorCorner
                )
            }
            .onEnded { _ in
                handleDragBase = nil
                Task { await viewModel.endGesture() }
            }
    }

    /// ハンドルとアンカーの位置関係からアンカー側の角を判定する
    private func anchorCorner(handle: CGPoint, anchor: CGPoint) -> PlacementGesture.Corner {
        if anchor.x <= handle.x {
            return anchor.y <= handle.y ? .topLeft : .bottomLeft
        } else {
            return anchor.y <= handle.y ? .topRight : .bottomRight
        }
    }

    /// 辺ハンドルのドラッグ: 枠のアスペクトを変える（反対辺固定・画像は歪まない）
    private func edgeHandleGesture(placementID: UUID, edge: PlacementGesture.Edge, contentRect: LayoutRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta: Double
                switch edge {
                case .leading, .trailing:
                    delta = value.translation.width / contentRect.width
                case .top, .bottom:
                    delta = value.translation.height / contentRect.height
                }
                viewModel.updateStretchEdge(placementID: placementID, edge: edge, delta: delta)
            }
            .onEnded { _ in
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
        if viewModel.cropModePlacementID != nil {
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

    // MARK: - 下部ツールバーの共通部品（アイコン＋ラベル縦積み・横スクロールで崩れ防止）

    /// ツールバー1項目の見た目（アイコンの上に小さなラベル）。等幅にして整列させる。
    private func toolItemLabel(_ title: String, systemImage: String, tint: Color = .accentColor) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .frame(height: 24)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint)
        .frame(width: 62)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func toolButton(
        _ title: String, systemImage: String, role: ButtonRole? = nil,
        identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            toolItemLabel(title, systemImage: systemImage, tint: role == .destructive ? .red : .accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    /// 項目が画面幅を超えても崩れないよう横スクロールに載せる共通コンテナ
    private func toolbarStrip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                content()
            }
            .padding(.horizontal, 12)
        }
    }

    /// 書き出し: ページを1枚で / 各写真を個別に（汎用。SNS別モードは持たない）
    @ViewBuilder
    private var exportMenu: some View {
        if viewModel.isExporting {
            ProgressView()
        } else if viewModel.currentPagePhotoCount >= 2 {
            Menu {
                Button {
                    Task { await viewModel.exportPages() }
                } label: {
                    Label(viewModel.pageCount > 1 ? "各ページを1枚ずつ書き出す" : "ページを1枚で書き出す",
                          systemImage: "doc")
                }
                Button {
                    Task { await viewModel.exportIndividualPhotos() }
                } label: {
                    Label("各写真を個別に書き出す（\(viewModel.currentPagePhotoCount)枚）",
                          systemImage: "square.grid.2x2")
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!viewModel.hasPhoto)
            .accessibilityIdentifier("pageEditor.export")
        } else {
            Button {
                Task { await viewModel.exportPages() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!viewModel.hasPhoto)
            .accessibilityIdentifier("pageEditor.export")
        }
    }

    /// 枠アスペクトのプリセット（写真は歪まずクロップ窓が変わる）
    private static let frameAspectChoices: [(label: String, pixelAspect: Double)] = [
        ("1:1", 1.0),
        ("4:5 縦", 4.0 / 5.0),
        ("3:4 縦", 3.0 / 4.0),
        ("16:9 横", 16.0 / 9.0)
    ]

    /// 写真選択中のメニュー
    private var photoControls: some View {
        toolbarStrip {
            Menu {
                Button("元画像の比率（全体を表示）") {
                    Task { await viewModel.applyPhotoNativeAspect() }
                }
                ForEach(Self.frameAspectChoices, id: \.label) { choice in
                    Button(choice.label) {
                        Task { await viewModel.applyFrameAspect(pixelAspect: choice.pixelAspect) }
                    }
                }
            } label: {
                toolItemLabel("枠比率", systemImage: "aspectratio")
            }
            .accessibilityIdentifier("pageEditor.frameAspectMenu")

            toolButton("全面", systemImage: "rectangle.arrowtriangle.2.inward",
                       identifier: "pageEditor.fillSelected") {
                Task { await viewModel.placeFillSelected() }
            }

            toolButton("マット", systemImage: "rectangle.arrowtriangle.2.outward",
                       identifier: "pageEditor.matSelected") {
                Task { await viewModel.placeMatSelected() }
            }

            toolButton("クロップ", systemImage: "crop", identifier: "pageEditor.cropButton") {
                if let id = viewModel.selectedPlacementID {
                    viewModel.toggleCropMode(id)
                }
            }

            Menu {
                Button {
                    Task { await viewModel.bringSelectedForward() }
                } label: {
                    Label("前面へ", systemImage: "square.2.stack.3d.top.filled")
                }
                Button {
                    Task { await viewModel.sendSelectedBackward() }
                } label: {
                    Label("背面へ", systemImage: "square.2.stack.3d.bottom.filled")
                }
            } label: {
                toolItemLabel("レイヤー", systemImage: "square.stack.3d.up")
            }
            .accessibilityIdentifier("pageEditor.layerMenu")

            toolButton("削除", systemImage: "trash", role: .destructive,
                       identifier: "pageEditor.deletePhoto") {
                Task { await viewModel.deleteSelectedPhoto() }
            }
        }
    }

    /// 非選択時のページ全体メニュー（全プロジェクト共通。SNS別の分岐はしない）
    private var pageMenuControls: some View {
        toolbarStrip {
            Menu {
                ForEach(Self.aspectChoices, id: \.label) { choice in
                    Button(choice.label) {
                        Task { await viewModel.setAspect(choice.aspect) }
                    }
                }
            } label: {
                toolItemLabel("比率", systemImage: "aspectratio")
            }
            .accessibilityIdentifier("pageEditor.aspectMenu")

            toolButton("分割", systemImage: "rectangle.split.3x1",
                       identifier: "pageEditor.split") {
                splitPickerPresented = true
            }

            templateMenu

            toolButton("全面", systemImage: "rectangle.arrowtriangle.2.inward",
                       identifier: "pageEditor.fillButton") {
                Task { await viewModel.placeFill() }
            }

            toolButton("マット", systemImage: "rectangle.arrowtriangle.2.outward",
                       identifier: "pageEditor.matButton") {
                Task { await viewModel.placeMat() }
            }

            framePresetMenu

            if viewModel.pageCount > 1 {
                Text("\(viewModel.currentPageIndex + 1)/\(viewModel.pageCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)
                    .accessibilityIdentifier("pageEditor.pageLabel")
            }
        }
    }

    /// テンプレート（スロット型枠）ピッカー: 現在スライドに型枠を敷く。
    /// 敷くと空スロット（＋）が出て、タップで写真を当てはめる（スロット先行）。
    private var templateMenu: some View {
        Menu {
            ForEach(viewModel.availableTemplates) { template in
                Button(template.name) {
                    Task { await viewModel.applyTemplate(template) }
                }
            }
        } label: {
            toolItemLabel("テンプレート", systemImage: "rectangle.split.2x2")
        }
        .accessibilityIdentifier("pageEditor.templateMenu")
    }

    private var framePresetMenu: some View {
        Menu {
            ForEach(Self.presetChoices, id: \.label) { choice in
                Button(choice.label) {
                    Task { await viewModel.applyPreset(choice.preset) }
                }
            }
        } label: {
            toolItemLabel("枠", systemImage: "square.dashed")
        }
        .accessibilityIdentifier("pageEditor.presetMenu")
    }

    /// 分割シート: スライド数を決めて、選んだ1枚をカルーセルへ割り付ける
    private var splitSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("1枚をカルーセルに分割")
                    .font(.headline)
                Text("選んだ写真を \(splitCount) 枚のスライドに切り、スワイプで繋がって見えるようにします。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Stepper("スライド数: \(splitCount)", value: $splitCount, in: 2...10)
                    .fixedSize()
                Spacer()
            }
            .padding(28)
            .navigationTitle("分割")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { pendingSplitData = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        let data = pendingSplitData
                        pendingSplitData = nil
                        if let data {
                            Task {
                                await viewModel.splitPhotoData(
                                    data, intoSlides: splitCount, slideAspect: viewModel.currentSlideAspect
                                )
                            }
                        }
                    }
                    .accessibilityIdentifier("split.apply")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
