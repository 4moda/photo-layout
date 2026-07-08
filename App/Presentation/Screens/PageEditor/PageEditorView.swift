import SwiftUI
import PhotosUI
import PhotoLayoutCore

/// ページ編集画面。プロジェクト種別で編集面が変わる:
/// - X投稿: タイムライン合成ビュー（全スロットを1画面に展開し、スロット内で写真をパン/ズーム）
/// - Instagram/自由: 自由変形エディタ（ドラッグ移動＋スナップ、ピンチ/角ハンドルで拡縮、
///   ダブルタップでクロップモード→枠外タップで完了）
struct PageEditorView: View {
    @State private var viewModel: PageEditorViewModel
    @State private var photoPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?
    /// ドラッグ中の対象と種別（ジェスチャ開始時に確定し、指を離すまで変えない）
    @State private var dragTargetID: UUID?
    @State private var dragIsCropPan = false
    /// 角ハンドルドラッグ開始時の角と中心（拡縮中に選択枠が動いても基準がぶれないよう固定）
    @State private var handleDragBase: (corner: CGPoint, center: CGPoint)?

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
            } else if let page = viewModel.page {
                CanvasRenderView(
                    page: page,
                    placements: viewModel.pagePlacements,
                    defaultFrame: viewModel.project.defaultPhotoFrame,
                    images: viewModel.previewImages
                )
                .overlay { editOverlay(page: page) }
                .shadow(radius: 4)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("pageEditor.canvas")

                if viewModel.cropModePlacementID != nil {
                    Text("クロップ調整中 — ドラッグ/ピンチで位置と拡大を変更、枠の外をタップで完了")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("pageEditor.cropModeHint")
                }

                if !viewModel.currentPageHasPhoto {
                    Button {
                        photoPickerPresented = true
                    } label: {
                        Label("写真を追加", systemImage: "photo.badge.plus")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("pageEditor.addPhotoEmpty")
                }

                pageControls
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

    // MARK: - 自由変形エディタ（Instagram/自由レイアウト）

    /// 選択枠・角ハンドル・スナップガイドの描画とジェスチャの受付。
    /// 座標変換はRenderPlanBuilderと同じPageGeometryを使う（触った場所＝描かれる場所）。
    private func editOverlay(page: PageEntity) -> some View {
        GeometryReader { geo in
            let size = LayoutSize(width: geo.size.width, height: geo.size.height)
            let contentRect = PageGeometry.contentRect(page: page, pageSize: size)

            ZStack {
                // スナップガイド線
                ForEach(Array(viewModel.activeGuides.enumerated()), id: \.offset) { _, guide in
                    guideLine(guide, contentRect: contentRect)
                }
                // 選択中の配置の枠と角ハンドル
                if let selectedID = viewModel.selectedPlacementID,
                   let placement = viewModel.pagePlacements.first(where: { $0.id == selectedID }) {
                    let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentRect)
                    let isCrop = viewModel.cropModePlacementID == selectedID
                    selectionChrome(rect: rect, isCrop: isCrop, placementID: selectedID)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(doubleTapGesture(contentRect: contentRect)
                .exclusively(before: singleTapGesture(contentRect: contentRect)))
            .simultaneousGesture(dragGesture(contentRect: contentRect))
            .simultaneousGesture(magnifyGesture())
        }
    }

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

    private func normalized(_ point: CGPoint, in contentRect: LayoutRect) -> (x: Double, y: Double) {
        (
            x: (point.x - contentRect.x) / contentRect.width,
            y: (point.y - contentRect.y) / contentRect.height
        )
    }

    private func doubleTapGesture(contentRect: LayoutRect) -> some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
            let p = normalized(value.location, in: contentRect)
            if let placement = viewModel.placement(atNormalizedX: p.x, y: p.y) {
                viewModel.toggleCropMode(placement.id)
            }
        }
    }

    /// 通常時: タップで選択/解除。クロップ中: 写真の外をタップしたら完了
    private func singleTapGesture(contentRect: LayoutRect) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let p = normalized(value.location, in: contentRect)
            let hit = viewModel.placement(atNormalizedX: p.x, y: p.y)
            if let cropID = viewModel.cropModePlacementID {
                if hit?.id != cropID {
                    viewModel.exitCropMode()
                }
            } else {
                viewModel.select(hit?.id)
            }
        }
    }

    private func dragGesture(contentRect: LayoutRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                // 対象はジェスチャ開始位置で1度だけ確定する
                if dragTargetID == nil {
                    let p = normalized(value.startLocation, in: contentRect)
                    guard let placement = viewModel.placement(atNormalizedX: p.x, y: p.y) else { return }
                    dragTargetID = placement.id
                    dragIsCropPan = viewModel.cropModePlacementID == placement.id
                    if !dragIsCropPan {
                        viewModel.select(placement.id)
                    }
                }
                guard let targetID = dragTargetID else { return }
                if dragIsCropPan,
                   let placement = viewModel.pagePlacements.first(where: { $0.id == targetID }) {
                    // クロップパンは枠（imageRect）に対する相対移動量
                    let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentRect)
                    viewModel.updateCropPan(
                        placementID: targetID,
                        translationX: value.translation.width / rect.width,
                        translationY: value.translation.height / rect.height
                    )
                } else {
                    viewModel.updateMove(
                        placementID: targetID,
                        translationX: value.translation.width / contentRect.width,
                        translationY: value.translation.height / contentRect.height
                    )
                }
            }
            .onEnded { _ in
                dragTargetID = nil
                dragIsCropPan = false
                Task { await viewModel.endGesture() }
            }
    }

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let targetID = viewModel.cropModePlacementID
                    ?? viewModel.selectedPlacementID
                    ?? viewModel.pagePlacements.last?.id else { return }
                if viewModel.cropModePlacementID == targetID {
                    viewModel.updateCropZoom(placementID: targetID, factor: value.magnification)
                } else {
                    viewModel.select(targetID)
                    viewModel.updateScale(placementID: targetID, factor: value.magnification)
                }
            }
            .onEnded { _ in
                Task { await viewModel.endGesture() }
            }
    }

    // MARK: - コントロール

    /// ページ切替＋追加/削除（Instagramカルーセルや自由レイアウトの複数ページ用）
    private var pageControls: some View {
        HStack(spacing: 16) {
            if viewModel.pageCount > 1 {
                Button {
                    viewModel.goToPage(viewModel.currentPageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(viewModel.currentPageIndex == 0)
                .accessibilityIdentifier("pageEditor.prevPage")

                Text("\(viewModel.currentPageIndex + 1) / \(viewModel.pageCount)")
                    .font(.subheadline.monospacedDigit())
                    .accessibilityIdentifier("pageEditor.pageLabel")

                Button {
                    viewModel.goToPage(viewModel.currentPageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(viewModel.currentPageIndex == viewModel.pageCount - 1)
                .accessibilityIdentifier("pageEditor.nextPage")
            }

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
            }
        }
        .buttonStyle(.bordered)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !viewModel.project.isXPost {
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
            }

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
        .buttonStyle(.bordered)
    }
}
