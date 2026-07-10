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
    @Test("AddPhoto: 保存された参照で自然配置のplacementが追加され永続化される")
    func addPhoto() async throws {
        let repo = InMemoryProjectRepository()
        let project = try await CreateProjectUseCase(repository: repo).execute()
        let updated = try await AddPhotoUseCase(photoStore: FakePhotoStore(), repository: repo)
            .execute(project: project, imageData: Data(count: 42))

        #expect(updated.placements.count == 1)
        #expect(updated.placements[0].photo.fileName == "stored-42.jpg")
        // 既定は自然配置: 元画像全体（クロップなし）を歪めず配置
        #expect(updated.placements[0].cropRect.isApproximatelyEqual(to: .unit))
        #expect(updated.placements[0].destRect.width <= 1.0)
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

    @Test("Mutations: 全面/マット配置とプリセット適用")
    func mutations() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        project.addPhoto(PhotoRef(fileName: "p.jpg", pixelWidth: 3000, pixelHeight: 2000))

        // 既定は自然配置: 元画像全体（クロップなし）を歪めず配置。cropは.unit、
        // destRectのpxアスペクト＝元画像アスペクト(1.5)
        #expect(project.placements[0].cropRect.isApproximatelyEqual(to: .unit))
        let dest = project.placements[0].destRect
        #expect(abs(dest.aspectRatio - 1.5) < 1e-9) // 1:1領域なので正規化=px
        #expect(dest.width <= 1.0 && dest.height <= 1.0) // 領域内に収まる

        project.placeAllMatted(coverage: 0.8)
        #expect(project.placements[0].cropRect.isApproximatelyEqual(to: .unit))
        #expect(abs(project.placements[0].destRect.width - 0.8) < 1e-9)          // 横長写真: 幅が律速
        #expect(abs(project.placements[0].destRect.aspectRatio - 1.5) < 1e-9)    // 1:1領域なので正規化=px

        project.applyFramePreset(.blackBackgroundWhiteBorder)
        #expect(project.pages[0].background.color == .black)
        #expect(project.defaultPhotoFrame.borderColor == .white)
        // 再配置後もマットのまま・写真全体が見えている
        #expect(project.placements[0].cropRect.isApproximatelyEqual(to: .unit))
    }

    @Test("複数追加は完全に重ならないよう少しずつずれる（カスケード）")
    func multipleAddCascades() {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let photo = PhotoRef(fileName: "p.jpg", pixelWidth: 3000, pixelHeight: 3000)
        project.addPhoto(photo)
        project.addPhoto(photo)
        project.addPhoto(photo)
        let d0 = project.orderedPlacements[0].destRect
        let d1 = project.orderedPlacements[1].destRect
        let d2 = project.orderedPlacements[2].destRect
        // 位置がずれている（完全一致しない）
        #expect(!d0.isApproximatelyEqual(to: d1))
        #expect(!d1.isApproximatelyEqual(to: d2))
        // サイズは同じ（元アスペクト・同スケール）
        #expect(abs(d0.width - d1.width) < 1e-9)
        #expect(abs(d1.x - d0.x - 0.05) < 1e-9) // 一定量ずつ右下へ
    }
}
