import SwiftUI
import PhotosUI
import PhotoLayoutCore

/// フェーズ2のページ編集画面: 単ページ・単写真＋枠＋書き出し。
struct PageEditorView: View {
    @State private var viewModel: PageEditorViewModel
    @State private var pickerItem: PhotosPickerItem?

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
                    placements: viewModel.project.orderedPlacements,
                    defaultFrame: viewModel.project.defaultPhotoFrame,
                    images: viewModel.previewImages
                )
                .shadow(radius: 4)
                .padding(.horizontal)
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("pageEditor.canvas")
            }

            if !viewModel.hasPhoto {
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
                Task { await viewModel.toggleContentMode() }
            } label: {
                Label(
                    viewModel.contentMode == .fill ? "fill" : "fit",
                    systemImage: viewModel.contentMode == .fill
                        ? "rectangle.arrowtriangle.2.inward"
                        : "rectangle.arrowtriangle.2.outward"
                )
            }
            .accessibilityIdentifier("pageEditor.modeToggle")

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
