import SwiftUI
import PhotoLayoutCore

/// SCRL風のサムネイルグリッド（1行3枚前後）。ProjectCell/FolderCellで共有する。
private let gridColumns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

/// 新規作成は「用紙サイズ（キャンバスのアスペクト）」だけ選ぶ。SNS別のモードは持たず、
/// ラベルは用途のヒントに留める。枠付けもレイアウトも同じ汎用プロジェクトで行う。
/// 「最近」の新規作成とフォルダ詳細での新規作成の両方から使うため file scope に置く。
private let canvasChoices: [AspectRatioOption] = AspectRatioOption.orderedAll

/// S01の上部モード切替。「Recent」は既存の全プロジェクト一覧、「Folder」は作成済みフォルダの一覧。
private enum ProjectListMode: String {
    case recent
    case folder
}

/// S01のナビゲーション先。ProjectEntity/FolderEntityを1本のNavigationStackで扱うための型。
private enum ProjectListRoute: Hashable {
    case project(ProjectEntity)
    case folder(FolderEntity)
    case settings
}

/// 下書き一覧。行タップでページ編集へ遷移する。
/// 新規作成は［＋］メニューで投稿先（X / Instagram / 自由）を選んでから。
/// 写真はエディタ内で追加する（一覧では選ばせない）。
struct ProjectListView: View {
    @State private var viewModel: ProjectListViewModel
    @State private var path: [ProjectListRoute] = []
    @State private var mode: ProjectListMode = .recent
    @State private var showingNewProjectSheet = false
    @State private var showingNewFolderSheet = false
    @State private var newFolderName = ""
    /// 「Recent」グリッドの複数選択モード。Recent⇔Folder切替や画面遷移をまたいでは保持しない
    /// （切り替えたら選択はクリアされる想定。フォルダ詳細側は`FolderDetailView`が自身の状態を持つ）
    @State private var isSelectingRecent = false
    @State private var recentSelection: Set<UUID> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkFolderPicker = false

    init(viewModel: ProjectListViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    modePicker

                    Group {
                        switch mode {
                        case .recent: recentContent
                        case .folder: folderContent
                        }
                    }
                    .frame(maxHeight: .infinity)
                }

                if isSelectingRecent {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ProjectSelectionBar(
                                count: recentSelection.count,
                                idPrefix: "projectList.selection",
                                onCancel: exitRecentSelection,
                                onSetFolder: { showingBulkFolderPicker = true },
                                onDelete: { showingBulkDeleteConfirmation = true }
                            )
                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                } else {
                    addMenuButton
                }
            }
            .navigationTitle(isSelectingRecent ? "\(recentSelection.count)件選択中" : "PhotoLayout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: ProjectListRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("projectList.settings")
                }
            }
            .navigationDestination(for: ProjectListRoute.self) { route in
                switch route {
                case .project(let project):
                    AppComposition.makePageEditor(project: project)
                case .folder(let folder):
                    FolderDetailView(folder: folder, viewModel: viewModel, path: $path)
                case .settings:
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingNewProjectSheet) {
                NewProjectAspectSheet { aspect in
                    createAndOpen(aspect: aspect, title: nil)
                }
            }
            .sheet(isPresented: $showingNewFolderSheet) {
                newFolderSheet
            }
            .sheet(isPresented: $showingBulkDeleteConfirmation) {
                BulkDeleteConfirmationSheet(
                    count: recentSelection.count,
                    idPrefix: "projectList.bulkDelete",
                    onConfirm: {
                        let ids = recentSelection
                        showingBulkDeleteConfirmation = false
                        Task {
                            await viewModel.deleteProjects(ids: ids)
                            exitRecentSelection()
                        }
                    },
                    onCancel: { showingBulkDeleteConfirmation = false }
                )
            }
            .sheet(isPresented: $showingBulkFolderPicker) {
                BulkFolderPickerSheet(folders: viewModel.folders, idPrefix: "projectList.bulkMoveToFolder") { folderID in
                    let ids = recentSelection
                    showingBulkFolderPicker = false
                    Task {
                        await viewModel.moveProjectsToFolder(ids: ids, folderID: folderID)
                        exitRecentSelection()
                    }
                }
            }
            // 編集画面から戻ったときにも最新を読み直す（.taskは初回のみのため）
            .onAppear {
                Task { await viewModel.load() }
            }
        }
    }

    private func exitRecentSelection() {
        isSelectingRecent = false
        recentSelection = []
    }

    /// 「Recent」「Folder」の切替。セグメントコントロール相当を手組みし、
    /// アプリ内の他シート（枠比率シート等）と統一感のあるスタイルにする。
    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton(.recent, title: "最近")
            modeButton(.folder, title: "フォルダ")
        }
        .padding(4)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func modeButton(_ target: ProjectListMode, title: String) -> some View {
        Button {
            mode = target
            exitRecentSelection()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == target ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Capsule().fill(mode == target ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("projectList.mode.\(target.rawValue)")
    }

    /// 「Recent」: 既存の全プロジェクト一覧（本Issue以前と挙動は変えない）
    private var recentContent: some View {
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
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(viewModel.projects) { project in
                            ProjectCell(
                                project: project,
                                thumbnailImages: viewModel.thumbnailImages(for: project),
                                folders: viewModel.folders,
                                isSelecting: isSelectingRecent,
                                isSelected: recentSelection.contains(project.id),
                                onDelete: { Task { await viewModel.delete(id: project.id) } },
                                onMoveToFolder: { folderID in
                                    Task { await viewModel.moveToFolder(projectID: project.id, folderID: folderID) }
                                },
                                onEnterSelection: {
                                    isSelectingRecent = true
                                    recentSelection = [project.id]
                                },
                                onToggleSelection: {
                                    if recentSelection.contains(project.id) {
                                        recentSelection.remove(project.id)
                                    } else {
                                        recentSelection.insert(project.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 80)
                }
                .accessibilityIdentifier("projectList.list")
            }
        }
    }

    /// 「Folder」: 作成済みフォルダの一覧。タップでそのフォルダのプロジェクトのみ表示する詳細画面へ。
    private var folderContent: some View {
        Group {
            if viewModel.folders.isEmpty {
                ContentUnavailableView(
                    "フォルダがありません",
                    systemImage: "folder",
                    description: Text("下のボタンでフォルダを作成")
                )
                .accessibilityIdentifier("projectList.folderEmpty")
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(viewModel.folders) { folder in
                            let folderProjects = viewModel.projects(inFolder: folder.id)
                            FolderCell(
                                folder: folder,
                                previewProject: folderProjects.first,
                                previewImages: folderProjects.first.map { viewModel.thumbnailImages(for: $0) } ?? [:],
                                projectCount: folderProjects.count,
                                onRename: { newName in
                                    Task { await viewModel.renameFolder(id: folder.id, name: newName) }
                                },
                                onDelete: { Task { await viewModel.deleteFolder(id: folder.id) } }
                            )
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 80)
                }
                .accessibilityIdentifier("projectList.folderList")
            }
        }
    }

    /// 単独の丸＋FAB。Xアプリの投稿ボタンのように背景パネルを持たず右下に単体配置する
    /// （2ボタン横並びの`.ultraThinMaterial`パネルは#82で廃止）。タップすると
    /// 「新規デザインを作成」「フォルダを作成」の2択メニューを表示し、両シート自体の
    /// フロー・見た目は変えず入り口だけを統合する。
    private var addMenuButton: some View {
        Menu {
            Button {
                showingNewProjectSheet = true
            } label: {
                Label("新規デザインを作成", systemImage: "square.and.pencil")
            }
            Button {
                newFolderName = ""
                showingNewFolderSheet = true
            } label: {
                Label("フォルダを作成", systemImage: "folder.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .accessibilityIdentifier("projectList.add")
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// フォルダ作成: 名前入力のみのシンプルなシート。
    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                TextField("フォルダ名", text: $newFolderName)
                    .accessibilityIdentifier("projectList.newFolder.field")
            }
            .navigationTitle("フォルダを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingNewFolderSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") {
                        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingNewFolderSheet = false
                        guard !trimmed.isEmpty else { return }
                        Task { await viewModel.createFolder(name: trimmed) }
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("projectList.newFolder.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createAndOpen(aspect: AspectRatio, title: String?) {
        Task {
            if let project = await viewModel.create(aspect: aspect, title: title) {
                path.append(.project(project))
            }
        }
    }
}

/// 用紙サイズ選択シート。`PageEditorView` の枠比率シート（S02-F09）と同じグリッド形式で、
/// 比率をドロップダウンではなく形プレビューで見せる。「Recent」の新規作成とフォルダ詳細
/// （`FolderDetailView`）でのフォルダ内新規作成の両方から使う共通シート。
private struct NewProjectAspectSheet: View {
    let onSelect: (AspectRatio) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                    spacing: 16
                ) {
                    ForEach(canvasChoices, id: \.rawValue) { choice in
                        Button {
                            dismiss()
                            onSelect(choice.aspect)
                        } label: {
                            // 比率は可視化された枠の中央に収め、下にSNS用途（サービス名/機能）を示す
                            VStack(spacing: 6) {
                                AspectRatioSwatch(aspect: choice.aspect.ratio, centerLabel: choice.label)
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
                        .accessibilityIdentifier("projectList.new_\(choice.rawValue)")
                    }
                }
                .padding(20)
            }
            .navigationTitle("用紙サイズを選んで新規作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// フォルダ詳細。そのフォルダの`folderID`を持つプロジェクトだけを既存の`ProjectCell`/グリッドで表示する。
/// 下部フローティングの＋ボタンから、最初からこのフォルダに属する新規プロジェクトを作成できる。
/// 既存プロジェクトをこのフォルダへ移動する（またはここから他フォルダ/未分類へ移す）操作は
/// `ProjectCell`の「⋯」メニュー→「フォルダへ移動」から行う（このフォルダ詳細画面にも同じセルが並ぶ）。
private struct FolderDetailView: View {
    let folder: FolderEntity
    let viewModel: ProjectListViewModel
    @Binding var path: [ProjectListRoute]
    @State private var showingNewProjectSheet = false
    /// このフォルダ詳細だけの複数選択モード。画面を離れる（戻る）と`@State`ごと破棄されるため、
    /// 「Recent」側の選択やモード切替とは独立している（受け入れ条件どおり選択は画面をまたがない）。
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var showingBulkDeleteConfirmation = false
    @State private var showingBulkFolderPicker = false

    private var projects: [ProjectEntity] {
        viewModel.projects(inFolder: folder.id)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView(
                        "このフォルダにはレイアウトがありません",
                        systemImage: "folder",
                        description: Text("＋でこのフォルダに新しいレイアウトを作成、またはプロジェクトをこのフォルダへ移動すると、ここに表示されます")
                    )
                    .accessibilityIdentifier("projectList.folderDetail.empty")
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(projects) { project in
                                ProjectCell(
                                    project: project,
                                    thumbnailImages: viewModel.thumbnailImages(for: project),
                                    folders: viewModel.folders,
                                    isSelecting: isSelecting,
                                    isSelected: selection.contains(project.id),
                                    onDelete: { Task { await viewModel.delete(id: project.id) } },
                                    onMoveToFolder: { folderID in
                                        Task { await viewModel.moveToFolder(projectID: project.id, folderID: folderID) }
                                    },
                                    onEnterSelection: {
                                        isSelecting = true
                                        selection = [project.id]
                                    },
                                    onToggleSelection: {
                                        if selection.contains(project.id) {
                                            selection.remove(project.id)
                                        } else {
                                            selection.insert(project.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(12)
                        .padding(.bottom, 80)
                    }
                    .accessibilityIdentifier("projectList.folderDetail.list")
                }
            }
            .frame(maxHeight: .infinity)

            if isSelecting {
                ProjectSelectionBar(
                    count: selection.count,
                    idPrefix: "projectList.folderDetail.selection",
                    onCancel: exitSelection,
                    onSetFolder: { showingBulkFolderPicker = true },
                    onDelete: { showingBulkDeleteConfirmation = true }
                )
                .padding(.bottom, 12)
            } else {
                newProjectButton
            }
        }
        .navigationTitle(isSelecting ? "\(selection.count)件選択中" : folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectAspectSheet { aspect in
                createAndOpen(aspect: aspect)
            }
        }
        .sheet(isPresented: $showingBulkDeleteConfirmation) {
            BulkDeleteConfirmationSheet(
                count: selection.count,
                idPrefix: "projectList.folderDetail.bulkDelete",
                onConfirm: {
                    let ids = selection
                    showingBulkDeleteConfirmation = false
                    Task {
                        await viewModel.deleteProjects(ids: ids)
                        exitSelection()
                    }
                },
                onCancel: { showingBulkDeleteConfirmation = false }
            )
        }
        .sheet(isPresented: $showingBulkFolderPicker) {
            BulkFolderPickerSheet(folders: viewModel.folders, idPrefix: "projectList.folderDetail.bulkMoveToFolder") { folderID in
                let ids = selection
                showingBulkFolderPicker = false
                Task {
                    await viewModel.moveProjectsToFolder(ids: ids, folderID: folderID)
                    exitSelection()
                }
            }
        }
    }

    private func exitSelection() {
        isSelecting = false
        selection = []
    }

    /// `ProjectListView.bottomFloatingMenu`と同じ見た目・位置の＋のみの版。フォルダ作成ボタンは
    /// ここでは不要（既にフォルダの中にいるため）。
    private var newProjectButton: some View {
        Button {
            showingNewProjectSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.28), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        .padding(.bottom, 8)
        .accessibilityIdentifier("projectList.folderDetail.add")
    }

    private func createAndOpen(aspect: AspectRatio) {
        Task {
            if let project = await viewModel.create(aspect: aspect, title: nil, folderID: folder.id) {
                path.append(.project(project))
            }
        }
    }
}

/// 一覧のサムネイルセル。名前は出さず、1ページ目のプレビューを正方形カードで見せる。
/// タップで編集へ、右上「⋯」メニューでフォルダへ移動・削除。
private struct ProjectCell: View {
    let project: ProjectEntity
    /// 1ページ目の配置ID→サムネイル画像（ViewModelのキャッシュから供給）
    let thumbnailImages: [UUID: UIImage]
    /// 「フォルダへ移動」ピッカーに並べる作成済みフォルダ一覧
    let folders: [FolderEntity]
    /// 複数選択モード中かどうか（true の間はタップがエディタ遷移ではなく選択トグルになる）
    let isSelecting: Bool
    let isSelected: Bool
    let onDelete: () -> Void
    /// 選んだフォルダのIDを渡す。「フォルダなし」を選んだ場合はnil（未分類に戻す）
    let onMoveToFolder: (UUID?) -> Void
    /// 「⋯」メニューの「選択」または長押しで呼ばれる。このプロジェクトを選択済みの状態で選択モードへ入る
    let onEnterSelection: () -> Void
    /// 選択モード中にセルをタップしたときの選択/解除トグル
    let onToggleSelection: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var showingFolderPicker = false

    private var displayTitle: String {
        project.title ?? "無題のレイアウト"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isSelecting {
                    Button(action: onToggleSelection) {
                        thumbnail
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: ProjectListRoute.project(project)) {
                        thumbnail
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier(displayTitle)
            .selectionHighlight(isSelecting && isSelected, in: RoundedRectangle(cornerRadius: 12))
            .onLongPressGesture(minimumDuration: 0.5) {
                guard !isSelecting else { return }
                onEnterSelection()
            }

            if !isSelecting {
                Menu {
                    Button {
                        onEnterSelection()
                    } label: {
                        Label("選択", systemImage: "checkmark.circle")
                    }
                    Button {
                        showingFolderPicker = true
                    } label: {
                        Label("フォルダへ移動", systemImage: "folder")
                    }
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
        }
        // 注: ここで .accessibilityIdentifier を付けると子（NavigationLink）へ伝播して
        // タイトルidentifierを上書きしてしまうため付けない（UIテストはタイトルでタップする）
        .sheet(isPresented: $showingDeleteConfirmation) {
            deleteConfirmationSheet
        }
        .sheet(isPresented: $showingFolderPicker) {
            folderPickerSheet
        }
    }

    /// フォルダへ移動ピッカー: 作成済みフォルダ一覧＋「フォルダなし」（未分類に戻す）。
    /// 現在の所属先には枠のハイライト＋チェックマークを付ける。「Folder」モードのフォルダ一覧
    /// （`folderContent`/`FolderCell`）と同じグリッド・カードの見た目に統一する
    /// （テキスト行のみの`List`だとフォルダ選択画面と見た目がバラバラになるため）。
    private var folderPickerSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    FolderPickerCard(
                        title: "フォルダなし",
                        systemImage: "tray",
                        isSelected: project.folderID == nil
                    ) {
                        showingFolderPicker = false
                        onMoveToFolder(nil)
                    }
                    .accessibilityIdentifier("projectList.moveToFolder.none")

                    ForEach(folders) { folder in
                        FolderPickerCard(
                            title: folder.name,
                            systemImage: "folder.fill",
                            isSelected: project.folderID == folder.id
                        ) {
                            showingFolderPicker = false
                            onMoveToFolder(folder.id)
                        }
                        .accessibilityIdentifier("projectList.moveToFolder.\(folder.name)")
                    }
                }
                .padding(12)
            }
            .navigationTitle("フォルダへ移動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingFolderPicker = false }
                        .accessibilityIdentifier("projectList.moveToFolder.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
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

/// フォルダへ移動ピッカーの1枚。「Folder」モードの`FolderCell`と同じ正方形カード
/// （アイコン＋下にキャプション、`systemGray5`の枠）で見た目を揃える。選択中（現在の所属先）は
/// 枠をアクセントカラーで強調し、右上にチェックマークバッジを重ねる。
private struct FolderPickerCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: systemImage)
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color(.systemGray5), lineWidth: isSelected ? 2 : 0.5)
                    )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                    }
                }

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 複数選択モード中の下部フローティングバー（キャンセル／フォルダを設定／削除）。
/// `PageOverviewView.overviewControls`と同じ`.ultraThinMaterial`ピルの見た目に揃える。
/// 「Recent」グリッドとフォルダ詳細グリッドの両方で同じ選択モードUIを提供するため共有する。
private struct ProjectSelectionBar: View {
    let count: Int
    /// 画面ごとにaccessibilityIdentifierを分けるためのプレフィックス
    let idPrefix: String
    let onCancel: () -> Void
    let onSetFolder: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            actionButton("キャンセル", systemImage: "xmark", action: onCancel)
                .accessibilityIdentifier("\(idPrefix).cancel")
            actionButton("フォルダを設定", systemImage: "folder", action: onSetFolder)
                .disabled(count == 0)
                .accessibilityIdentifier("\(idPrefix).setFolder")
            actionButton("削除", systemImage: "trash", tint: .red, action: onDelete)
                .disabled(count == 0)
                .accessibilityIdentifier("\(idPrefix).delete")
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
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
    }
}

/// 複数選択モードの「まとめて削除」確認シート。単体削除確認シート（拡大サムネイル付き）と違い
/// 複数の異なるレイアウトが対象のためサムネイルは持たず、件数のみを示す。
private struct BulkDeleteConfirmationSheet: View {
    let count: Int
    let idPrefix: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)

                VStack(spacing: 6) {
                    Text("選択した\(count)件を削除しますか？")
                        .font(.headline)
                    Text("削除すると元に戻せません")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    Button(role: .destructive, action: onConfirm) {
                        Text("削除").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityIdentifier("\(idPrefix).confirm")

                    Button(action: onCancel) {
                        Text("キャンセル").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("\(idPrefix).cancel")
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 24)
        }
        .presentationDetents([.medium])
    }
}

/// 複数選択モードの「フォルダを設定」ピッカー。既存の単体「フォルダへ移動」ピッカーと同じ
/// グリッド・カード見た目を流用するが、対象が複数プロジェクトで所属先がまちまちのため
/// 現在の所属先のハイライトは付けない（`isSelected`は常にfalse）。
private struct BulkFolderPickerSheet: View {
    let folders: [FolderEntity]
    let idPrefix: String
    let onSelect: (UUID?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    FolderPickerCard(title: "フォルダなし", systemImage: "tray", isSelected: false) {
                        onSelect(nil)
                    }
                    .accessibilityIdentifier("\(idPrefix).none")

                    ForEach(folders) { folder in
                        FolderPickerCard(title: folder.name, systemImage: "folder.fill", isSelected: false) {
                            onSelect(folder.id)
                        }
                        .accessibilityIdentifier("\(idPrefix).\(folder.name)")
                    }
                }
                .padding(12)
            }
            .navigationTitle("フォルダを設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 背後の選択モードバーにも「キャンセル」があるため、UIテストが
                    // 一意にタップできるようidentifierを付ける
                    Button("キャンセル") { dismiss() }
                        .accessibilityIdentifier("\(idPrefix).cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 「Folder」一覧のセル。タップでフォルダ詳細へ、右上「⋯」メニューで名称変更・削除
/// （`ProjectCell`の⋯メニュー→確認シートと同じパターン）。
private struct FolderCell: View {
    let folder: FolderEntity
    /// フォルダ内で最新更新のプロジェクト（`projects`は更新日時降順のためfirstで求まる）。
    /// サムネイルをフォルダに収めて可視化するために使う。nilなら未分類0件のフォルダ。
    let previewProject: ProjectEntity?
    let previewImages: [UUID: UIImage]
    let projectCount: Int
    let onRename: (String) -> Void
    let onDelete: () -> Void
    @State private var showingRenameSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var renameText = ""

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: ProjectListRoute.folder(folder)) {
                card
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(folder.name)

            Menu {
                Button {
                    renameText = folder.name
                    showingRenameSheet = true
                } label: {
                    Label("名前を変更", systemImage: "pencil")
                }
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
            .accessibilityIdentifier("projectList.folderMenu")
        }
        .sheet(isPresented: $showingRenameSheet) {
            renameSheet
        }
        .sheet(isPresented: $showingDeleteConfirmation) {
            deleteConfirmationSheet
        }
    }

    private var card: some View {
        VStack(spacing: 6) {
            thumbnail

            Text(folder.name)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// フォルダ内最新プロジェクトの1ページ目サムネイルをフォルダに収めて可視化する
    /// （空フォルダはフォルダアイコンのまま）。件数バッジは`ProjectCell`のページ数バッジと
    /// 同じ見た目・位置にして一覧内での視覚言語を揃える。
    private var thumbnail: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let previewProject, let page = previewProject.orderedPages.first {
                CanvasRenderView(
                    page: page,
                    placements: SpreadGeometry.visiblePlacements(onPage: page.index, project: previewProject),
                    defaultFrame: previewProject.defaultPhotoFrame,
                    images: previewImages
                )
                .padding(10)
                folderIconBadge
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
            }
            if projectCount > 0 {
                countBadge
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }

    /// サムネイルがプロジェクトの写真で埋まるため、フォルダであることを示す小バッジを左上に添える。
    private var folderIconBadge: some View {
        VStack {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .padding(6)
                Spacer()
            }
            Spacer()
        }
    }

    private var countBadge: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Text("\(projectCount)件")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .padding(6)
            }
        }
    }

    private var renameSheet: some View {
        NavigationStack {
            Form {
                TextField("フォルダ名", text: $renameText)
                    .accessibilityIdentifier("projectList.folderRename.field")
            }
            .navigationTitle("名前を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingRenameSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingRenameSheet = false
                        guard !trimmed.isEmpty else { return }
                        onRename(trimmed)
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("projectList.folderRename.confirm")
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// フォルダ削除確認。プロジェクト削除確認（拡大サムネイル付き）と違い実体の見た目を持たないため、
    /// フォルダアイコン＋テキストのみ。「フォルダ内のレイアウトは削除されない」ことを明記する。
    private var deleteConfirmationSheet: some View {
        VStack {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 6) {
                    Text("このフォルダを削除しますか？")
                        .font(.headline)
                    Text("「\(folder.name)」を削除します。フォルダ内のレイアウトは削除されず「Recent」に残ります")
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
}
