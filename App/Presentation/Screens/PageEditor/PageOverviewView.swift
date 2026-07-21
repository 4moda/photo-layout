import SwiftUI
import PhotoLayoutCore

/// ページ俯瞰モード: 全ページのサムネイルを「横並び」で一覧し、挿入・削除・並べ替えを行う。
/// ページは横スクロールで2〜3ページ分が見える。並べ替えはドラッグ&ドロップで行う。
/// 左上=キャンセル（開始時点へ復帰）、右上=完了（確定して保存）。
struct PageOverviewView: View {
    @Bindable var viewModel: PageEditorViewModel
    @State private var selectedPageIndex: Int?
    @State private var activePicker: OverviewPicker?

    /// 比率・背景色ピッカーの種類。Menuのドロップダウンでは項目の形/色が実機で正しく描画されない
    /// ことが分かったため、`PageEditorView` の枠比率シート（S02-F09）と同様のグリッドシートに統一している。
    private enum OverviewPicker: String, Identifiable {
        case ratio
        case background
        var id: String { rawValue }
    }

    /// サムネイルの高さ。ページのアスペクトに応じて幅が決まる（2〜3ページ分が見える目安）
    private let thumbnailHeight: CGFloat = 200

    private static let aspectChoices: [AspectRatioOption] = AspectRatioOption.orderedAll

    private static let aspectTolerance: Double = 1e-6

    /// 現在のページアスペクトと比率シートの選択肢が一致するか（幅:高さの表現差を無視し実際の比で比較）
    private func isCurrentAspect(_ aspect: AspectRatio) -> Bool {
        guard let current = viewModel.page?.aspect else { return false }
        return abs(current.ratio - aspect.ratio) < Self.aspectTolerance
    }

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
                PLColor.graphite.ignoresSafeArea()
                carousel
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        overviewControls
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
            }
            .sheet(item: $activePicker) { picker in
                Group {
                    switch picker {
                    case .ratio: ratioPickerSheet
                    case .background: backgroundColorPickerSheet
                    }
                }
                // 既定のガラス素材は背後のカルーセルが強く透けて読みにくいため不透明寄りに
                .presentationBackground(.regularMaterial)
            }
        }
    }

    // MARK: - カルーセル

    /// ページカードの横スクロールカルーセル。`overviewControls` 分の下部領域を除いた
    /// 表示可能領域内で上下中央に配置する（`overviewControls` は `safeAreaInset` で分離）。
    private var carousel: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
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
                .padding(.vertical, 20)
            }
            Spacer(minLength: 0)
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
                Button {
                    activePicker = .ratio
                } label: {
                    controlLabel("比率", systemImage: "aspectratio")
                }
                .accessibilityIdentifier("overview.ratio")

                Button {
                    activePicker = .background
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

    // MARK: - ピッカーシート（S02-F09の枠比率シートと同じグリッド形式）

    private var ratioPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                    spacing: 16
                ) {
                    ForEach(Self.aspectChoices, id: \.rawValue) { choice in
                        Button {
                            viewModel.overviewSetAspect(choice.aspect)
                            activePicker = nil
                        } label: {
                            // S01の用紙サイズシートと同じ見せ方（比率は枠の中央・下にSNS用途）
                            VStack(spacing: 6) {
                                AspectRatioSwatch(aspect: choice.aspect.ratio, centerLabel: choice.label)
                                    .selectionHighlight(
                                        isCurrentAspect(choice.aspect),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                VStack(spacing: 1) {
                                    Text(choice.captionService)
                                    Text(choice.captionUsage)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(choice.label)
                    }
                }
                .padding(20)
            }
            .navigationTitle("比率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { activePicker = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 背景色ピッカー。色名テキストは出さず、丸スウォッチのグリッドから選ばせる。
    /// Menuのドロップダウン項目では塗り色が実機で描画されなかったため、枠比率シートと同じ
    /// 独立シートに切り替えた。将来カスタムカラー等を足す場合もこのグリッドに項目を追加するだけでよい。
    private var backgroundColorPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 4), spacing: 20) {
                    ForEach(Self.backgroundColors, id: \.label) { choice in
                        Button {
                            viewModel.overviewSetBackgroundColor(choice.color)
                            activePicker = nil
                        } label: {
                            BackgroundColorSwatch(color: choice.color, diameter: 52)
                                .selectionHighlight(viewModel.page?.background.color == choice.color, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(choice.label)
                        .accessibilityLabel(choice.label)
                    }
                }
                .padding(20)
            }
            .navigationTitle("背景色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { activePicker = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 背景色ピッカーの1項目。色名は出さず、該当色で塗った丸のみで選ばせる。
private struct BackgroundColorSwatch: View {
    let color: LayoutColor
    let diameter: CGFloat

    var body: some View {
        Circle()
            .fill(Color(red: color.red, green: color.green, blue: color.blue, opacity: color.alpha))
            .frame(width: diameter, height: diameter)
            // 白・薄グレーがシート地に同化しないよう、輪郭線は全色にはっきり付ける
            .overlay(Circle().strokeBorder(PLColor.hairline, lineWidth: 1))
    }
}
