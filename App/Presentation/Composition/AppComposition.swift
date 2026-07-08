import SwiftUI
import SwiftData
import PhotoLayoutCore

/// DIコンポジションルート。Infrastructureの具象実装をUseCaseへ、UseCaseをViewModelへ
/// 結線するのはこのファイルだけ（Clean Architectureの"main"に相当）。
@MainActor
enum AppComposition {
    static let container = try! ModelContainer(
        for: ProjectModel.self, PageModel.self, PlacementModel.self
    )

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
                listProjects: ListProjectsUseCase(repository: repo)
            )
            : nil
        let viewModel = ProjectListViewModel(
            listProjects: ListProjectsUseCase(repository: repo),
            createProject: CreateProjectUseCase(repository: repo),
            deleteProject: DeleteProjectUseCase(repository: repo),
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
            imageProvider: PreviewImageProvider(decoder: decoder)
        )
        return PageEditorView(viewModel: viewModel)
    }
}
