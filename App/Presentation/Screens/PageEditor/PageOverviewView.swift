import SwiftUI
import PhotoLayoutCore

/// ページ俯瞰モード: 全ページのサムネイルを「横並び」で一覧し、挿入・削除・並べ替えを行う。
/// ページは横スクロールで2〜3ページ分が見える。並べ替えはドラッグ&ドロップで行う。
/// 左上=キャンセル（開始時点へ復帰）、右上=完了（確定して保存）。
struct PageOverviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    @State private var selectedPageIndex: Int?

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
            ZStack(alignment: .bottom) {
                Color(white: 0.11).ignoresSafeArea()
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 10) {
                        let pages = viewModel.project.orderedPages
                        ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                            card(for: page, showsInsertAfter: offset < pages.count - 1)
                                // ドラッグで並べ替え（このカードへドロップ＝その位置へ移動）
                                .draggable("\(page.index)")
                                .dropDestination(for: String.self) { items, _ in
                                    guard let from = items.first.flatMap(Int.init) else { return false }
                                    selectedPageIndex = nil
                                    viewModel.overviewMovePage(from: from, to: page.index)
                                    return true
                                }
                        }
                        appendCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
                overviewControls
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
            }
        }
    }

    // MARK: - ページカード

    /// スライド1枚のカード。タップで選択し、並べ替えはドラッグ&ドロップで行う。
    private func card(for page: PageEntity, showsInsertAfter: Bool) -> some View {
        let isCurrent = page.index == viewModel.currentPageIndex
        let isSelected = page.index == selectedPageIndex
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
                    .stroke(
                        isSelected ? Color.accentColor
                                   : (isCurrent ? Color.white.opacity(0.82) : Color.white.opacity(0.25)),
                        lineWidth: isSelected ? 3 : (isCurrent ? 1.5 : 0.5)
                    )
            )

            ZStack {
                Text("\(page.index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)

                if showsInsertAfter {
                    HStack {
                        Spacer()
                        insertButton(after: page.index)
                    }
                }
            }
            .frame(width: page.aspect.ratio * thumbnailHeight)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.focusPage(page.index)
            selectedPageIndex = (selectedPageIndex == page.index) ? nil : page.index
        }
        .accessibilityIdentifier("overview.row")
    }

    /// 末尾の「ページを追加」カード
    private var appendCard: some View {
        Button {
            selectedPageIndex = nil
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
        .accessibilityIdentifier("overview.append")
    }

    /// ページの連続性を崩さないよう、カードの下側に出す挿入ボタン
    private func insertButton(after pageIndex: Int) -> some View {
        Button {
            selectedPageIndex = nil
            viewModel.overviewInsertPage(at: pageIndex + 1)
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("overview.insertBetween\(pageIndex + 1)")
    }

    @ViewBuilder
    private var overviewControls: some View {
        if let selectedPageIndex {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.overviewDuplicatePage(at: selectedPageIndex) }
                    self.selectedPageIndex = nil
                } label: {
                    controlLabel("複製", systemImage: "plus.square.on.square")
                }

                Button(role: .destructive) {
                    viewModel.overviewDeletePage(at: selectedPageIndex)
                    self.selectedPageIndex = nil
                } label: {
                    controlLabel("削除", systemImage: "trash", tint: .red)
                }
                .disabled(viewModel.pageCount <= 1)
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
        } else {
            HStack(spacing: 12) {
                Menu {
                    ForEach(Self.aspectChoices, id: \.label) { choice in
                        Button(choice.label) {
                            viewModel.overviewSetAspect(choice.aspect)
                        }
                    }
                } label: {
                    controlLabel("比率", systemImage: "aspectratio")
                }
                .accessibilityIdentifier("overview.ratio")

                Menu {
                    ForEach(Self.backgroundColors, id: \.label) { choice in
                        Button(choice.label) {
                            viewModel.overviewSetBackgroundColor(choice.color)
                        }
                    }
                } label: {
                    controlLabel("背景", systemImage: "square.dashed")
                }
                .accessibilityIdentifier("overview.background")
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
    }

    private func controlLabel(_ title: String, systemImage: String, tint: Color = .accentColor) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
            Text(title)
                .font(.caption2)
        }
        .foregroundStyle(tint)
        .frame(width: 62)
        .padding(.vertical, 6)
    }
}
