import SwiftUI
import SwiftData
import PhotoLayoutCore

/// DIコンポジションルート。Infrastructureの具象実装をUseCaseへ、UseCaseをViewModelへ
/// 結線するのはこのファイルだけ（Clean Architectureの"main"に相当）。
@MainActor
enum AppComposition {
    static let shared = try! makeContainer()

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: ProjectModel.self, PageModel.self, PlacementModel.self)
    }

    static func makeRootView() -> some View {
        let repository = SwiftDataProjectRepository(modelContext: shared.mainContext)
        let viewModel = ProjectListViewModel(
            listProjects: ListProjectsUseCase(repository: repository),
            createProject: CreateProjectUseCase(repository: repository),
            deleteProject: DeleteProjectUseCase(repository: repository)
        )
        return ProjectListView(viewModel: viewModel)
    }
}
