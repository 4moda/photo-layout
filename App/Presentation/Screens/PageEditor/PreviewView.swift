import SwiftUI
import PhotoLayoutCore

/// 書き出しプレビュー画面。右上の保存ボタンで遷移し、各スライドの仕上がりを確認してから保存する。
/// 複数スライドは左右スワイプのカルーセル（`TabView(.page)`）で1枚ずつ表示する。
struct PreviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $currentPage) {
                ForEach(Array(viewModel.project.orderedPages.enumerated()), id: \.element.id) { index, page in
                    let placements = SpreadGeometry.visiblePlacements(
                        onPage: page.index, project: viewModel.project)

                    VStack(spacing: 6) {
                        CanvasRenderView(
                            page: page,
                            placements: placements,
                            defaultFrame: viewModel.project.defaultPhotoFrame,
                            images: viewModel.previewImages
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                        if viewModel.pageCount > 1 {
                            PageDotsIndicator(pageCount: viewModel.pageCount, currentIndex: currentPage)
                        }

                        let size = ExportSizeCalculator.pageSize(
                            page: page, placements: placements,
                            resolution: viewModel.exportResolution)
                        Text("(\(Int(size.width)) × \(Int(size.height)) px)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding()
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .navigationTitle("プレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            .alert("書き出し", isPresented: Binding(
                get: { viewModel.exportMessage != nil },
                set: { if !$0 { viewModel.exportMessage = nil } }
            )) {
                Button("OK") { viewModel.exportMessage = nil }
            } message: {
                Text(viewModel.exportMessage ?? "")
            }
            .sheet(isPresented: Binding(
                get: { viewModel.shareItems != nil },
                set: { if !$0 { viewModel.shareItems = nil } }
            )) {
                if let items = viewModel.shareItems {
                    ActivityView(activityItems: items)
                }
            }
        }
    }

    /// 保存・共有バー。他画面（`PageEditorView`/`PageOverviewView`）と同じ、
    /// ultraThinMaterialの丸角フローティングメニューの見た目に揃える。
    private var saveBar: some View {
        VStack(spacing: 10) {
            // 書き出し解像度: 標準=元画像の実解像度優先 / 高解像度=長辺2048px最低保証。
            // 切り替えると上のpxサイズ表示が連動して変わる（効果の有無がその場で分かる）
            Picker("書き出し解像度", selection: $viewModel.exportResolution) {
                Text("標準").tag(ExportResolution.standard)
                Text("高解像度").tag(ExportResolution.high)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .accessibilityIdentifier("preview.resolution")

            saveButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        .padding(.bottom, 20)
    }

    private var saveButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.exportPages() }
            } label: {
                saveBarItem(
                    title: viewModel.pageCount > 1 ? "保存（全\(viewModel.pageCount)枚）" : "保存",
                    systemImage: "square.and.arrow.down",
                    isLoading: viewModel.isExporting
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting || viewModel.isPreparingShare || !viewModel.hasPhoto)
            .accessibilityIdentifier("preview.save")

            Button {
                Task { await viewModel.prepareShare() }
            } label: {
                saveBarItem(title: "共有", systemImage: "square.and.arrow.up", isLoading: viewModel.isPreparingShare)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isExporting || viewModel.isPreparingShare || !viewModel.hasPhoto)
            .accessibilityIdentifier("preview.share")
        }
    }

    /// フローティングメニュー1項目の見た目（アイコンの上に小さなラベル）。他画面の `toolButton` と同じ配置。
    private func saveBarItem(title: String, systemImage: String, isLoading: Bool) -> some View {
        VStack(spacing: 3) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 20))
                }
            }
            .frame(height: 24)
            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.accentColor)
        .frame(minWidth: 72)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Instagramの投稿ページネーションを模した、現在表示中のページ位置を示すドットインジケーター。
/// カルーセルのスワイプ位置（`currentPage`）に連動する。
private struct PageDotsIndicator: View {
    let pageCount: Int
    let currentIndex: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: index == currentIndex ? 7 : 5, height: index == currentIndex ? 7 : 5)
            }
        }
    }
}
