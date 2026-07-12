import SwiftUI
import PhotoLayoutCore

/// 下書き一覧。行タップでページ編集へ遷移する。
/// 新規作成は［＋］メニューで投稿先（X / Instagram / 自由）を選んでから。
/// 写真はエディタ内で追加する（一覧では選ばせない）。
struct ProjectListView: View {
    @State private var viewModel: ProjectListViewModel
    @State private var path: [ProjectEntity] = []
    @State private var showingNewProjectSheet = false

    init(viewModel: ProjectListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView(
                        "レイアウトがありません",
                        systemImage: "rectangle.3.group",
                        description: Text("＋で新しいレイアウトを作成")
                    )
                    .accessibilityIdentifier("projectList.empty")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                            ForEach(viewModel.projects) { project in
                                ProjectCell(
                                    project: project,
                                    thumbnailImages: viewModel.thumbnailImages(for: project),
                                    onDelete: { Task { await viewModel.delete(id: project.id) } }
                                )
                            }
                        }
                        .padding(12)
                    }
                    .accessibilityIdentifier("projectList.list")
                }
            }
            .navigationTitle("PhotoLayout")
            .navigationDestination(for: ProjectEntity.self) { project in
                AppComposition.makePageEditor(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProjectSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("projectList.add")
                }
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                newProjectSheet
            }
            // 編集画面から戻ったときにも最新を読み直す（.taskは初回のみのため）
            .onAppear {
                Task { await viewModel.load() }
            }
        }
    }

    /// 新規作成は「用紙サイズ（キャンバスのアスペクト）」だけ選ぶ。SNS別のモードは持たず、
    /// ラベルは用途のヒントに留める。枠付けもレイアウトも同じ汎用プロジェクトで行う。
    private static let canvasChoices: [(id: String, label: String, aspect: AspectRatio)] = [
        ("square", "正方形 1:1", AspectRatio(width: 1, height: 1)),
        ("portrait45", "縦長 4:5（Instagram）", AspectRatio(width: 4, height: 5)),
        ("portrait34", "縦 3:4（X 1枚）", AspectRatio(width: 3, height: 4)),
        ("landscape169", "横 16:9", AspectRatio(width: 16, height: 9)),
        ("landscape191", "横長 1.91:1（Instagram）", AspectRatio(width: 1.91, height: 1))
    ]

    /// 用紙サイズ選択シート。`PageEditorView` の枠比率シート（S02-F09）と同じグリッド形式で、
    /// 比率をドロップダウンではなく形プレビューで見せる。
    private var newProjectSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(Self.canvasChoices, id: \.id) { choice in
                        Button {
                            showingNewProjectSheet = false
                            createAndOpen(aspect: choice.aspect, title: nil)
                        } label: {
                            VStack(spacing: 6) {
                                AspectRatioSwatch(aspect: choice.aspect.ratio)
                                Text(choice.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("projectList.new_\(choice.id)")
                    }
                }
                .padding(20)
            }
            .navigationTitle("用紙サイズを選んで新規作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingNewProjectSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func createAndOpen(aspect: AspectRatio, title: String?) {
        Task {
            if let project = await viewModel.create(aspect: aspect, title: title) {
                path.append(project)
            }
        }
    }

    /// SCRL風のサムネイルグリッド（1行3枚前後）。名前は表示しない。
    private static let gridColumns = [GridItem(.adaptive(minimum: 108), spacing: 12)]
}

/// 一覧のサムネイルセル。名前は出さず、1ページ目のプレビューを正方形カードで見せる。
/// タップで編集へ、右上「⋯」メニューで削除。
private struct ProjectCell: View {
    let project: ProjectEntity
    /// 1ページ目の配置ID→サムネイル画像（ViewModelのキャッシュから供給）
    let thumbnailImages: [UUID: UIImage]
    let onDelete: () -> Void
    @State private var showingDeleteConfirmation = false

    private var displayTitle: String {
        project.title ?? "無題のレイアウト"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: project) {
                thumbnail
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(displayTitle)

            Menu {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("削除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .padding(6)
            }
            .accessibilityIdentifier("projectList.menu")
        }
        // 注: ここで .accessibilityIdentifier を付けると子（NavigationLink）へ伝播して
        // タイトルidentifierを上書きしてしまうため付けない（UIテストはタイトルでタップする）
        .sheet(isPresented: $showingDeleteConfirmation) {
            deleteConfirmationSheet
        }
    }

    /// 削除確認。ユーザはタイトル（「枠付き（黒背景）」等の説明的な文字列）ではなく
    /// サムネイル写真でレイアウトを認知しているため、`confirmationDialog`（テキストのみ）ではなく
    /// 拡大サムネイルを添えた確認シートにする。タイトル・ページ数のテキストはVoiceOver向けに残す。
    private var deleteConfirmationSheet: some View {
        VStack {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                thumbnail
                    .frame(width: 200, height: 200)
                    .accessibilityIdentifier("projectList.deleteConfirm.thumbnail")

                VStack(spacing: 6) {
                    Text("このレイアウトを削除しますか？")
                        .font(.headline)
                    Text("\(displayTitle)・\(project.pages.count)ページの内容が完全に削除されます")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = false
                        onDelete()
                    } label: {
                        Text("削除").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showingDeleteConfirmation = false
                    } label: {
                        Text("キャンセル").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)
        }
        .presentationDetents([.medium])
    }

    private var thumbnail: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let page = project.orderedPages.first {
                CanvasRenderView(
                    page: page,
                    placements: SpreadGeometry.visiblePlacements(onPage: page.index, project: project),
                    defaultFrame: project.defaultPhotoFrame,
                    images: thumbnailImages
                )
                .padding(6)
            }
            // 複数ページはページ数バッジで示す
            if project.pages.count > 1 {
                pageBadge
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    private var pageBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("\(project.pages.count)ページ")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .padding(6)
            }
        }
    }
}
