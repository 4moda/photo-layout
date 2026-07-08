import SwiftUI
import PhotoLayoutCore

/// ページ俯瞰モード: 全ページのサムネイルを一覧し、挿入・削除・並べ替えを行う。
/// 左上=キャンセル（開始時点へ復帰）、右上=完了（確定して保存）。
struct PageOverviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    /// 1ページ目以外も含む、全配置のサムネイル画像（配置ID→画像）
    let thumbnailImages: [UUID: UIImage]

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.project.orderedPages, id: \.id) { page in
                    row(for: page)
                }
                .onMove { offsets, destination in
                    viewModel.overviewMovePage(fromOffsets: offsets, toOffset: destination)
                }
                .onDelete { offsets in
                    // 各ページを詰めながら消えるので、大きいindexから削除する
                    for index in offsets.sorted(by: >) {
                        viewModel.overviewDeletePage(at: index)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("ページの編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { viewModel.cancelOverview() }
                        .accessibilityIdentifier("overview.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        Task { await viewModel.confirmOverview() }
                    }
                    .accessibilityIdentifier("overview.done")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.overviewInsertPage(at: viewModel.pageCount)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("overview.append")
                }
            }
        }
    }

    private func row(for page: PageEntity) -> some View {
        HStack(spacing: 12) {
            CanvasRenderView(
                page: page,
                placements: viewModel.project.placements(onPage: page.index),
                defaultFrame: viewModel.project.defaultPhotoFrame,
                images: thumbnailImages
            )
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray4), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("ページ \(page.index + 1)")
                    .font(.headline)
                Text("\(viewModel.project.placements(onPage: page.index).count)枚")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.overviewInsertPage(at: page.index + 1)
            } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("overview.insertAfter\(page.index)")
        }
        .accessibilityIdentifier("overview.row")
    }
}
