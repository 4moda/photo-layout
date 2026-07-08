import SwiftUI
import PhotoLayoutCore

/// 下書き一覧。行タップでページ編集へ遷移する。
/// 新規作成は［＋］メニューで投稿先（X / Instagram / 自由）を選んでから。
/// 写真はエディタ内で追加する（一覧では選ばせない）。
struct ProjectListView: View {
    @State private var viewModel: ProjectListViewModel
    @State private var path: [ProjectEntity] = []

    init(viewModel: ProjectListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.projects.isEmpty {
                    ContentUnavailableView(
                        "下書きがありません",
                        systemImage: "rectangle.3.group",
                        description: Text("＋で新しいレイアウトを作成")
                    )
                    .accessibilityIdentifier("projectList.empty")
                } else {
                    List {
                        ForEach(viewModel.projects) { project in
                            NavigationLink(value: project) {
                                ProjectRow(
                                    project: project,
                                    thumbnailImages: viewModel.thumbnailImages(for: project)
                                )
                            }
                        }
                        .onDelete { offsets in
                            let ids = offsets.map { viewModel.projects[$0].id }
                            Task {
                                for id in ids { await viewModel.delete(id: id) }
                            }
                        }
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
                    newProjectMenu
                }
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

    private var newProjectMenu: some View {
        Menu {
            Section("用紙サイズを選んで新規作成") {
                ForEach(Self.canvasChoices, id: \.id) { choice in
                    Button(choice.label) {
                        createAndOpen(aspect: choice.aspect, title: nil)
                    }
                    .accessibilityIdentifier("projectList.new_\(choice.id)")
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("projectList.add")
    }

    private func createAndOpen(aspect: AspectRatio, title: String?) {
        Task {
            if let project = await viewModel.create(aspect: aspect, title: title) {
                path.append(project)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectEntity
    /// 1ページ目の配置ID→サムネイル画像（ViewModelのキャッシュから供給）
    let thumbnailImages: [UUID: UIImage]

    var body: some View {
        HStack(spacing: 12) {
            if let page = project.orderedPages.first {
                CanvasRenderView(
                    page: page,
                    placements: project.placements(onPage: page.index),
                    defaultFrame: project.defaultPhotoFrame,
                    images: thumbnailImages
                )
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
                .accessibilityIdentifier("projectList.thumbnail")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title ?? "無題のレイアウト")
                    .font(.headline)
                Text("\(project.pages.count)ページ・\(project.placements.count)枚 — \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("projectList.row")
    }
}
