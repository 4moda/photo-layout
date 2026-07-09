import SwiftUI
import PhotoLayoutCore

/// ページ俯瞰モード: 全ページのサムネイルを「横並び」で一覧し、挿入・削除・並べ替えを行う。
/// ページは横スクロールで2〜3ページ分が見える。並べ替えは各カードの左右ボタンで行う。
/// 左上=キャンセル（開始時点へ復帰）、右上=完了（確定して保存）。
struct PageOverviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    /// 1ページ目以外も含む、全配置のサムネイル画像（配置ID→画像）
    let thumbnailImages: [UUID: UIImage]

    /// サムネイルの高さ。ページのアスペクトに応じて幅が決まる（2〜3ページ分が見える目安）
    private let thumbnailHeight: CGFloat = 200

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(viewModel.project.orderedPages, id: \.id) { page in
                        card(for: page)
                    }
                    appendCard
                }
                .padding(20)
            }
            .background(Color(white: 0.11))
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

    // MARK: - ページカード

    private func card(for page: PageEntity) -> some View {
        let isCurrent = page.index == viewModel.currentPageIndex
        let count = viewModel.project.placements(onPage: page.index).count
        return VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                CanvasRenderView(
                    page: page,
                    placements: viewModel.project.placements(onPage: page.index),
                    defaultFrame: viewModel.project.defaultPhotoFrame,
                    images: thumbnailImages
                )
                .frame(width: page.aspect.ratio * thumbnailHeight, height: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.accentColor : Color.white.opacity(0.25),
                                lineWidth: isCurrent ? 2.5 : 0.5)
                )

                // 削除（最後の1ページは残す）
                Button {
                    viewModel.overviewDeletePage(at: page.index)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .padding(6)
                .disabled(viewModel.pageCount <= 1)
                .opacity(viewModel.pageCount <= 1 ? 0.3 : 1)
                .accessibilityIdentifier("overview.delete\(page.index)")
            }

            Text("ページ \(page.index + 1) ・ \(count)枚")
                .font(.caption)
                .foregroundStyle(.white)

            // 並べ替え（左右）と挿入
            HStack(spacing: 14) {
                Button {
                    viewModel.overviewMovePage(from: page.index, to: page.index - 1)
                } label: {
                    Image(systemName: "chevron.left.circle")
                }
                .disabled(page.index == 0)
                .accessibilityIdentifier("overview.moveLeft\(page.index)")

                Button {
                    viewModel.overviewInsertPage(at: page.index + 1)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityIdentifier("overview.insertAfter\(page.index)")

                Button {
                    viewModel.overviewMovePage(from: page.index, to: page.index + 1)
                } label: {
                    Image(systemName: "chevron.right.circle")
                }
                .disabled(page.index >= viewModel.pageCount - 1)
                .accessibilityIdentifier("overview.moveRight\(page.index)")
            }
            .font(.title3)
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("overview.row")
    }

    /// 末尾の「ページを追加」カード
    private var appendCard: some View {
        Button {
            viewModel.overviewInsertPage(at: viewModel.pageCount)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 32))
                Text("ページを追加")
                    .font(.caption)
            }
            .foregroundStyle(.white.opacity(0.8))
            .frame(width: 130, height: thumbnailHeight)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overview.appendCard")
    }
}
