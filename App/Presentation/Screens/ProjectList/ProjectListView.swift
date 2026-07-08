import SwiftUI
import PhotosUI
import PhotoLayoutCore

/// 下書き一覧。行タップでページ編集へ遷移する。
/// ツールバー: ＋=空の下書き、X=写真1〜4枚を選んでX投稿プロジェクトを自動生成。
struct ProjectListView: View {
    @State private var viewModel: ProjectListViewModel
    @State private var path: [ProjectEntity] = []
    @State private var showXPicker = false
    @State private var xPickerItems: [PhotosPickerItem] = []

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
                                ProjectRow(project: project)
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
                    Button {
                        Task { await viewModel.createDraft() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("projectList.add")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showXPicker = true
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .accessibilityIdentifier("projectList.addX")
                }
            }
            .photosPicker(
                isPresented: $showXPicker,
                selection: $xPickerItems,
                maxSelectionCount: PlatformSpecTable.xMaxPhotoCount,
                matching: .images
            )
            .onChange(of: xPickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    // 選択順＝投稿順を保つため直列にロードする
                    var dataList: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            dataList.append(data)
                        }
                    }
                    xPickerItems = []
                    guard !dataList.isEmpty else { return }
                    if let project = await viewModel.createXPost(imageDataList: dataList) {
                        path.append(project)
                    }
                }
            }
            // 編集画面から戻ったときにも最新を読み直す（.taskは初回のみのため）
            .onAppear {
                Task { await viewModel.load() }
            }
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title ?? "無題のレイアウト")
                .font(.headline)
            Text("\(project.pages.count)ページ・\(project.placements.count)枚 — \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("projectList.row")
    }
}
