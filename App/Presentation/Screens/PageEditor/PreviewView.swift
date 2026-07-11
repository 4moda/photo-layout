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
            .safeAreaInset(edge: .bottom) { saveBar }
            .alert("書き出し", isPresented: Binding(
                get: { viewModel.exportMessage != nil },
                set: { if !$0 { viewModel.exportMessage = nil } }
            )) {
                Button("OK") { viewModel.exportMessage = nil }
            } message: {
                Text(viewModel.exportMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        VStack(spacing: 10) {
            Button {
                Task { await viewModel.exportPages() }
            } label: {
                Group {
                    if viewModel.isExporting {
                        ProgressView()
                    } else {
                        Label(viewModel.pageCount > 1 ? "カメラロールに保存（全\(viewModel.pageCount)枚）"
                                                       : "カメラロールに保存",
                              systemImage: "square.and.arrow.down")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isExporting || !viewModel.hasPhoto)
            .accessibilityIdentifier("preview.save")
        }
        .padding()
        .background(.bar)
    }
}
