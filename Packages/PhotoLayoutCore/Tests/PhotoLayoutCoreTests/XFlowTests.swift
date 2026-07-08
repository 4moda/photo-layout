import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("X複数枚フロー")
struct XFlowTests {
    @Test("3枚: 枚数別アスペクトのページが生成され、各写真が対応ページへ全面配置される")
    func createXPostThreePhotos() async throws {
        let repo = InMemoryProjectRepository()
        let useCase = CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
        let project = try await useCase.execute(
            imageDataList: [Data(count: 1), Data(count: 2), Data(count: 3)],
            framePreset: .whiteMargin
        )

        #expect(project.platformPreset == .x(photoCount: 3))
        let pages = project.orderedPages
        #expect(pages.map(\.aspect) == PlatformSpecTable.xPageAspects(photoCount: 3))

        // 各ページに1枚ずつ、全面配置＋そのページのアスペクトでクロップ
        for pageIndex in 0..<3 {
            let onPage = project.placements(onPage: pageIndex)
            #expect(onPage.count == 1)
            #expect(onPage[0].destRect.isApproximatelyEqual(to: .unit))
            let page = pages[pageIndex]
            let crop = onPage[0].cropRect
            let photo = onPage[0].photo
            let cropPxAspect = (crop.width * Double(photo.pixelWidth)) / (crop.height * Double(photo.pixelHeight))
            #expect(abs(cropPxAspect - page.contentAspect) < 1e-9)
        }
        // 永続化確認
        #expect(try await repo.fetch(id: project.id) == project)
    }

    @Test("0枚・5枚はエラー")
    func invalidCounts() async throws {
        let useCase = CreateXPostUseCase(photoStore: FakePhotoStore(), repository: InMemoryProjectRepository())
        await #expect(throws: CreateXPostError.invalidPhotoCount(0)) {
            _ = try await useCase.execute(imageDataList: [])
        }
        await #expect(throws: CreateXPostError.invalidPhotoCount(5)) {
            _ = try await useCase.execute(imageDataList: Array(repeating: Data(count: 1), count: 5))
        }
    }

    @Test("executeAll: 全ページが投稿順に書き出される")
    func exportAllInOrder() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(imageDataList: [Data(count: 1), Data(count: 2), Data(count: 3)])

        let exporter = FakeImageExporter()
        let saver = FakeLibrarySaver()
        let results = try await ExportPageUseCase(renderer: exporter, librarySaver: saver)
            .executeAll(project: project)

        #expect(results.count == 3)
        #expect(await saver.savedCount == 3)
        // ページ1(8:9・縦長)とページ2(16:9・横長)で出力アスペクトが異なる
        let aspect0 = results[0].pixelSize.width / results[0].pixelSize.height
        let aspect1 = results[1].pixelSize.width / results[1].pixelSize.height
        #expect(abs(aspect0 - 8.0 / 9.0) < 0.01)
        #expect(abs(aspect1 - 16.0 / 9.0) < 0.01)
    }

    @Test("書き出しは各ページに属する写真だけを含む")
    func exportUsesOnlyPagePlacements() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(imageDataList: [Data(count: 1), Data(count: 2)])

        let exporter = FakeImageExporter()
        _ = try await ExportPageUseCase(renderer: exporter, librarySaver: FakeLibrarySaver())
            .execute(project: project, pageIndex: 1)
        let plan = await exporter.lastPlan
        let imageCommands = plan.filter { if case .drawImage = $0 { return true }; return false }
        #expect(imageCommands.count == 1)
    }
}
