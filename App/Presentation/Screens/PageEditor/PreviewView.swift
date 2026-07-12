import SwiftUI
import PhotoLayoutCore

/// 書き出しプレビュー画面。右上の保存ボタンで遷移し、各スライドの仕上がりを確認してから保存する。
struct PreviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(viewModel.project.orderedPages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 6) {
                            CanvasRenderView(
                                page: page,
                                placements: SpreadGeometry.visiblePlacements(
                                    onPage: page.index, project: viewModel.project),
                                defaultFrame: viewModel.project.defaultPhotoFrame,
                                images: viewModel.previewImages
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

                            if viewModel.pageCount > 1 {
                                Text("\(index + 1) / \(viewModel.pageCount)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
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
