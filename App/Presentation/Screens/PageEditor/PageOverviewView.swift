import SwiftUI
import PhotoLayoutCore

/// ページ俯瞰モード: 全ページのサムネイルを「横並び」で一覧し、挿入・削除・並べ替えを行う。
/// ページは横スクロールで2〜3ページ分が見える。並べ替えは各カードの左右ボタンで行う。
/// 左上=キャンセル（開始時点へ復帰）、右上=完了（確定して保存）。
struct PageOverviewView: View {
    @Bindable var viewModel: PageEditorViewModel

    /// サムネイルの高さ。ページのアスペクトに応じて幅が決まる（2〜3ページ分が見える目安）
    private let thumbnailHeight: CGFloat = 200

    private static let aspectChoices: [(label: String, aspect: AspectRatio)] = [
        ("3:4 縦 (X 1枚)", AspectRatio(width: 3, height: 4)),
        ("4:5 縦 (Instagram)", AspectRatio(width: 4, height: 5)),
        ("1:1", AspectRatio(width: 1, height: 1)),
        ("1.91:1 横 (Instagram)", AspectRatio(width: 1.91, height: 1)),
        ("16:9 横", AspectRatio(width: 16, height: 9))
    ]

    /// プロジェクト共通の背景色（俯瞰・新規作成で設定）
    private static let backgroundColors: [(label: String, color: LayoutColor)] = [
        ("白", .white),
        ("薄グレー", LayoutColor(red: 0.92, green: 0.92, blue: 0.92)),
        ("グレー", LayoutColor(red: 0.5, green: 0.5, blue: 0.5)),
        ("濃グレー", LayoutColor(red: 0.17, green: 0.17, blue: 0.17)),
        ("黒", .black)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(white: 0.11).ignoresSafeArea()
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 16) {
                        let pages = viewModel.project.orderedPages
                        ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                            card(for: page)
                                // ドラッグで並べ替え（このカードへドロップ＝その位置へ移動）
                                .draggable("\(page.index)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let from = items.first.flatMap(Int.init) else { return false }
                                    viewModel.overviewMovePage(from: from, to: page.index)
                                    return true
                                }
                            if offset < pages.count - 1 {
                                insertCard(at: page.index + 1)
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
                ToolbarItem(placement: .bottomBar) {
                    // カルーセル全体の比率（スライド管理画面に置く。確定は完了時）
                    Menu {
                        ForEach(Self.aspectChoices, id: \.label) { choice in
                            Button(choice.label) {
                                viewModel.overviewSetAspect(choice.aspect)
                            }
                        }
                    } label: {
                        Label("比率", systemImage: "aspectratio")
                    }
                    .accessibilityIdentifier("overview.ratio")
                }
                ToolbarItem(placement: .bottomBar) { Spacer() }
                ToolbarItem(placement: .bottomBar) {
                    // プロジェクト共通の背景色（全スライドに適用。確定は完了時）
                    Menu {
                        ForEach(Self.backgroundColors, id: \.label) { choice in
                            Button(choice.label) {
                                viewModel.overviewSetBackgroundColor(choice.color)
                            }
                        }
                    } label: {
                        Label("背景", systemImage: "square.dashed")
                    }
                    .accessibilityIdentifier("overview.background")
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
                images: viewModel.previewImages
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
            Task { await viewModel.overviewDuplicatePage(at: page.index) }
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

    /// ページ間へ直接差し込むための挿入ボタン
    private func insertCard(at index: Int) -> some View {
        Button {
            viewModel.overviewInsertPage(at: index)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                Text("追加")
                    .font(.caption2)
            }
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 52, height: thumbnailHeight)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overview.insertBetween\(index)")
    }
}
