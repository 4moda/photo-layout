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
            ZStack {
                Color(white: 0.11).ignoresSafeArea()
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(viewModel.project.orderedPages, id: \.id) { page in
                            card(for: page)
                                // ドラッグで並べ替え（このカードへドロップ＝その位置へ移動）
                                .draggable("\(page.index)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let from = items.first.flatMap(Int.init) else { return false }
                                    viewModel.overviewMovePage(from: from, to: page.index)
                                    return true
                                }
                        }
                        appendCard
                    }
                    .padding(20)
                }
            }
            .navigationTitle("スライド")
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

    /// スライド1枚のカード。長押しで SCRL 風メニュー（左に追加/右に追加/複製/移動/削除）。
    private func card(for page: PageEntity) -> some View {
        let isCurrent = page.index == viewModel.currentPageIndex
        return VStack(spacing: 8) {
            CanvasRenderView(
                page: page,
                placements: SpreadGeometry.visiblePlacements(onPage: page.index, project: viewModel.project),
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

            Text("\(page.index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
            // 長押しでメニューが出る操作可能さを示すハンドル（文字なし）
            Image(systemName: "line.3.horizontal")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
        }
        .contentShape(Rectangle())
        .contextMenu { pageCardMenu(for: page) }
        .accessibilityIdentifier("overview.row")
    }

    @ViewBuilder
    private func pageCardMenu(for page: PageEntity) -> some View {
        Button {
            viewModel.overviewInsertPage(at: page.index)
        } label: { Label("左に追加", systemImage: "arrow.left.to.line") }
        Button {
            viewModel.overviewInsertPage(at: page.index + 1)
        } label: { Label("右に追加", systemImage: "arrow.right.to.line") }
        Button {
            viewModel.overviewDuplicatePage(at: page.index)
        } label: { Label("複製", systemImage: "plus.square.on.square") }
        Divider()
        Button {
            viewModel.overviewMovePage(from: page.index, to: page.index - 1)
        } label: { Label("左へ移動", systemImage: "arrow.left") }
            .disabled(page.index == 0)
        Button {
            viewModel.overviewMovePage(from: page.index, to: page.index + 1)
        } label: { Label("右へ移動", systemImage: "arrow.right") }
            .disabled(page.index >= viewModel.pageCount - 1)
        Divider()
        Button(role: .destructive) {
            viewModel.overviewDeletePage(at: page.index)
        } label: { Label("削除", systemImage: "trash") }
            .disabled(viewModel.pageCount <= 1)
    }

    /// 末尾の「ページを追加」カード
    private var appendCard: some View {
        Button {
            viewModel.overviewInsertPage(at: viewModel.pageCount)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 32))
                Text("スライドを追加")
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
