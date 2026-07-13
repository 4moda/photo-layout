import SwiftUI
import SwiftData
import PhotoLayoutCore

/// DIコンポジションルート。Infrastructureの具象実装をUseCaseへ、UseCaseをViewModelへ
/// 結線するのはこのファイルだけ（Clean Architectureの"main"に相当）。
@MainActor
enum AppComposition {
    /// UIテスト/スクショ撮影用に `--reset-store` でインメモリ・ストアへ切替える。
    /// 起動ごとに空から始まるため、空状態やデモ投入の結果を決定論的に撮影できる。
    static let container: ModelContainer = {
        let inMemory = CommandLine.arguments.contains("--reset-store")
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try! ModelContainer(
            for: ProjectModel.self, PageModel.self, PlacementModel.self,
            configurations: config
        )
    }()

    private static var repository: SwiftDataProjectRepository {
        SwiftDataProjectRepository(modelContext: container.mainContext)
    }

    private static let decoder = ImageIODecoder()

    static func makeRootView() -> some View {
        let repo = repository
        let seeder: DemoProjectSeeder? = CommandLine.arguments.contains("--seed-demo")
            ? DemoProjectSeeder(
                createProject: CreateProjectUseCase(repository: repo),
                addPhoto: AddPhotoUseCase(photoStore: FilePhotoStore(), repository: repo),
                createXPost: CreateXPostUseCase(photoStore: FilePhotoStore(), repository: repo),
                listProjects: ListProjectsUseCase(repository: repo),
                saveProject: SaveProjectUseCase(repository: repo)
            )
            : nil
        let viewModel = ProjectListViewModel(
            listProjects: ListProjectsUseCase(repository: repo),
            createProject: CreateProjectUseCase(repository: repo),
            deleteProject: DeleteProjectUseCase(repository: repo),
            thumbnailProvider: PreviewImageProvider(decoder: decoder, maxPixelSize: 256),
            seedDemo: seeder.map { s in { await s.seedIfNeeded() } }
        )
        return ProjectListView(viewModel: viewModel)
    }

    static func makePageEditor(project: ProjectEntity) -> some View {
        let repo = repository
        let viewModel = PageEditorViewModel(
            project: project,
            saveProject: SaveProjectUseCase(repository: repo),
            addPhoto: AddPhotoUseCase(photoStore: FilePhotoStore(), repository: repo),
            exportPage: ExportPageUseCase(
                renderer: CoreGraphicsExportRenderer(decoder: decoder),
                librarySaver: PHPhotoLibrarySaveAdapter()
            ),
            imageProvider: PreviewImageProvider(decoder: decoder),
            shareFileWriter: TemporaryShareFileWriter()
        )
        return PageEditorView(viewModel: viewModel)
    }
}
