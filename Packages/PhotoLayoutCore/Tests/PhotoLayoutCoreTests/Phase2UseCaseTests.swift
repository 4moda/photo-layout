import Foundation
import Testing
@testable import PhotoLayoutCore

// MARK: - フェイクPort実装

actor FakePhotoStore: PhotoStoring {
    func store(imageData: Data) async throws -> PhotoRef {
        PhotoRef(fileName: "stored-\(imageData.count).jpg", pixelWidth: 6000, pixelHeight: 4000)
    }
}

actor FakeImageExporter: ImageExporting {
    private(set) var lastPlan: [DrawCommand] = []
    private(set) var lastPixelSize: LayoutSize?

    func render(plan: [DrawCommand], pixelSize: LayoutSize, format: ExportFormat) async throws -> Data {
        lastPlan = plan
        lastPixelSize = pixelSize
        return Data(count: 123_456)
    }
}

actor FakeLibrarySaver: PhotoLibrarySaving {
    private(set) var savedCount = 0
    func save(imageData: Data) async throws { savedCount += 1 }
}

// MARK: - Tests

@Suite("Phase 2 UseCases")
struct Phase2UseCaseTests {
    @Test("AddPhoto: 保存された参照でplacementが追加され永続化される")
    func addPhoto() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateProjectUseCase(repository: repo).execute()
        let updated = try await AddPhotoUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(project: project, imageData: Data(count: 42))

        #expect(updated.placements.count == 1)
        #expect(updated.placements[0].photo.fileName == "stored-42.jpg")
        #expect(updated.placements[0].destRect == .unit)
        let persisted = try await repo.fetch(id: project.id)
        #expect(persisted?.placements.count == 1)
    }

    @Test("ExportPage: サイズ計算→プラン生成→描画→ライブラリ保存が繋がる")
    func exportPage() async throws {
        var project = ProjectEntity(
            pages: [PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5))]
        )
        project.addPhoto(PhotoRef(fileName: "p.jpg", pixelWidth: 4000, pixelHeight: 5000))

        let exporter = FakeImageExporter()
        let saver = FakeLibrarySaver()
        let result = try await ExportPageUseCase(renderer: exporter, librarySaver: saver)
            .execute(project: project, pageIndex: 0)

        #expect(result.pixelSize.height == 4096) // 4096クランプ
        #expect(result.byteCount == 123_456)
        #expect(await saver.savedCount == 1)
        let plan = await exporter.lastPlan
        #expect(plan.count == 2) // 背景 + 画像（枠なし）
    }

    @Test("ExportPage: 存在しないページはエラー")
    func exportMissingPage() async throws {
        let project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        await #expect(throws: ExportError.pageNotFound) {
            _ = try await ExportPageUseCase(renderer: FakeImageExporter(), librarySaver: FakeLibrarySaver())
                .execute(project: project, pageIndex: 3)
        }
    }

    @Test("Mutations: アスペクト変更・fill/fit切替・プリセット適用")
    func mutations() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.addPhoto(PhotoRef(fileName: "p.jpg", pixelWidth: 100, pixelHeight: 100))

        project.setPageAspect(AspectRatio(width: 16, height: 9))
        #expect(project.pages[0].aspect == AspectRatio(width: 16, height: 9))

        project.setContentMode(.fit)
        #expect(project.placements[0].contentMode == .fit)

        project.applyFramePreset(.blackBackgroundWhiteBorder)
        #expect(project.pages[0].background.color == .black)
        #expect(project.defaultPhotoFrame.borderColor == .white)
    }
}
