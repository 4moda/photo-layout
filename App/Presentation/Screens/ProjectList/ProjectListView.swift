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

    private var newProjectMenu: some View {
        Menu {
            Section("X投稿（タイムライン表示で編集）") {
                ForEach(1...4, id: \.self) { count in
                    Button("写真\(count)枚") {
                        createAndOpen(preset: .x(photoCount: count), title: "X投稿（\(count)枚）")
                    }
                    .accessibilityIdentifier("projectList.newX\(count)")
                }
            }
            Section("Instagram") {
                Button("正方形 1:1") {
                    createAndOpen(preset: .instagram(aspect: .square, pageCount: 1), title: "Instagram 1:1")
                }
                .accessibilityIdentifier("projectList.newInstagramSquare")
                Button("縦長 4:5") {
                    createAndOpen(preset: .instagram(aspect: .portrait, pageCount: 1), title: "Instagram 4:5")
                }
                .accessibilityIdentifier("projectList.newInstagramPortrait")
                Button("横長 1.91:1") {
                    createAndOpen(preset: .instagram(aspect: .landscape, pageCount: 1), title: "Instagram 1.91:1")
                }
                .accessibilityIdentifier("projectList.newInstagramLandscape")
            }
            Button("自由レイアウト") {
                createAndOpen(preset: nil, title: nil)
            }
            .accessibilityIdentifier("projectList.newFree")
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityIdentifier("projectList.add")
    }

    private func createAndOpen(preset: PlatformPreset?, title: String?) {
        Task {
            if let project = await viewModel.create(preset: preset, title: title) {
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
