import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("X複数枚フロー（1ページ＋タイムラインテンプレート）")
struct XFlowTests {
    @Test("3枚: 1ページにXタイムラインテンプレートが適用され、各写真がスロットへ収まる")
    func createXPostThreePhotos() async throws {
        let repo = InMemoryProjectRepository()
        let useCase = CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
        let project = try await useCase.execute(
            imageDataList: [Data(count: 1), Data(count: 2), Data(count: 3)],
            framePreset: .whiteMargin
        )

        #expect(project.platformPreset == .x(photoCount: 3))
        #expect(project.isXPost)
        // 単一ページ・16:9
        #expect(project.pages.count == 1)
        #expect(project.pages[0].aspect == AspectRatio(width: 16, height: 9))

        // 3枚がタイムラインの3スロットへ配置される
        let onPage = project.placements(onPage: 0)
        #expect(onPage.count == 3)
        let slots = XTimelineComposite.slots(photoCount: 3)
        for (offset, placement) in onPage.enumerated() {
            #expect(placement.destRect.isApproximatelyEqual(to: slots[offset]))
        }
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

    @Test("executeSlots: 各スロットが個別画像として投稿順に書き出される")
    func exportSlotsInOrder() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(imageDataList: [Data(count: 1), Data(count: 2), Data(count: 3)])

        let exporter = FakeImageExporter()
        let saver = FakeLibrarySaver()
        let results = try await ExportPageUseCase(renderer: exporter, librarySaver: saver)
            .executeSlots(project: project, pageIndex: 0)

        #expect(results.count == 3)
        #expect(await saver.savedCount == 3)
        // スロット0(左大・8:9寄り)とスロット1(右上・16:9寄り)で出力アスペクトが異なる
        let slots = XTimelineComposite.slots(photoCount: 3)
        let canvas = XTimelineComposite.canvasAspect(photoCount: 3).ratio
        let expected0 = slots[0].aspectRatio * canvas
        let expected1 = slots[1].aspectRatio * canvas
        let aspect0 = results[0].pixelSize.width / results[0].pixelSize.height
        let aspect1 = results[1].pixelSize.width / results[1].pixelSize.height
        #expect(abs(aspect0 - expected0) / expected0 < 0.03)
        #expect(abs(aspect1 - expected1) / expected1 < 0.03)
    }

    @Test("executeSlots: 各スロット画像は写真1枚だけを含む")
    func slotExportContainsSinglePhoto() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateXPostUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(imageDataList: [Data(count: 1), Data(count: 2)])

        let exporter = FakeImageExporter()
        _ = try await ExportPageUseCase(renderer: exporter, librarySaver: FakeLibrarySaver())
            .executeSlots(project: project, pageIndex: 0)
        let plan = await exporter.lastPlan
        let imageCommands = plan.filter { if case .drawImage = $0 { return true }; return false }
        #expect(imageCommands.count == 1) // 最後に描画したスロット
    }
}
