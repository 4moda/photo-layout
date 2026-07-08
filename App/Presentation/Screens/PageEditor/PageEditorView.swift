import SwiftUI
import PhotosUI
import PhotoLayoutCore

/// ページ編集画面: プレビュー＋自由変形ジェスチャ＋枠プリセット＋書き出し。
/// 操作体系（SCRL/Canva型）: ドラッグ=移動（スナップ付き）、ピンチ=アスペクト固定拡縮、
/// ダブルタップ=クロップモード（枠を固定して中身をパン/ズーム）。
struct PageEditorView: View {
    @State private var viewModel: PageEditorViewModel
    @State private var pickerItem: PhotosPickerItem?
    /// ドラッグ中の対象と種別（ジェスチャ開始時に確定し、指を離すまで変えない）
    @State private var dragTargetID: UUID?
    @State private var dragIsCropPan = false

    init(viewModel: PageEditorViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private static let aspectChoices: [(label: String, aspect: AspectRatio)] = [
        ("3:4 縦 (X 1枚)", AspectRatio(width: 3, height: 4)),
        ("4:5 縦 (IG)", AspectRatio(width: 4, height: 5)),
        ("1:1", AspectRatio(width: 1, height: 1)),
        ("1.91:1 横 (IG)", AspectRatio(width: 1.91, height: 1)),
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
            if let page = viewModel.page {
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
            }

            if viewModel.cropModePlacementID != nil {
                Text("クロップ調整中 — ドラッグ/ピンチで位置と拡大を変更、ダブルタップで完了")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("pageEditor.cropModeHint")
            }

            if viewModel.pageCount > 1 {
                pageSwitcher
            }

            if !viewModel.currentPageHasPhoto {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("写真を選ぶ", systemImage: "photo.badge.plus")
                        .font(.headline)
                }
                .accessibilityIdentifier("pageEditor.addPhoto")
            }

            controls
        }
        .padding(.vertical)
        .navigationTitle(viewModel.project.title ?? "レイアウト")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    // MARK: - ジェスチャレイヤ

    /// 選択枠・スナップガイドの描画とジェスチャの受付。
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
                // 選択中の配置の枠
                if let selectedID = viewModel.selectedPlacementID,
                   let placement = viewModel.pagePlacements.first(where: { $0.id == selectedID }) {
                    let rect = PageGeometry.imageRect(destRect: placement.destRect, in: contentRect)
                    let isCrop = viewModel.cropModePlacementID == selectedID
                    Rectangle()
                        .stroke(
                            isCrop ? Color.orange : Color.accentColor,
                            style: StrokeStyle(lineWidth: 2, dash: isCrop ? [6, 4] : [])
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
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

    private func singleTapGesture(contentRect: LayoutRect) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            let p = normalized(value.location, in: contentRect)
            viewModel.select(viewModel.placement(atNormalizedX: p.x, y: p.y)?.id)
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
                    viewModel.select(placement.id)
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

    private var pageSwitcher: some View {
        HStack(spacing: 20) {
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
        .buttonStyle(.bordered)
    }

    private var controls: some View {
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
