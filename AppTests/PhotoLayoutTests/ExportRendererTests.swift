import XCTest
import UIKit
import PhotoLayoutCore
@testable import PhotoLayout

/// 書き出しパイプラインの実体テスト:
/// 生成画像を実ファイル経由でレンダリングし、出力が指定ピクセルサイズのJPEGであることを保証する。
final class ExportRendererTests: XCTestCase {
    private var tempDir: URL!
    private var store: FilePhotoStore!
    private var renderer: CoreGraphicsExportRenderer!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportRendererTests-\(UUID().uuidString)", isDirectory: true)
        store = FilePhotoStore(directory: tempDir)
        renderer = CoreGraphicsExportRenderer(decoder: ImageIODecoder(directory: tempDir))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeTestImageData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        }
        return image.jpegData(compressionQuality: 0.95)!
    }

    func testExportProducesExactPixelSizeJPEG() async throws {
        let photoRef = try await store.store(imageData: makeTestImageData(width: 1600, height: 1200))
        XCTAssertEqual(photoRef.pixelWidth, 1600)
        XCTAssertEqual(photoRef.pixelHeight, 1200)

        let page = PageEntity(
            index: 0,
            aspect: AspectRatio(width: 4, height: 5),
            background: FramePreset.whiteMarginBlackBorder.background
        )
        let placement = PlacementEntity(sortIndex: 0, photo: photoRef, destRect: .unit)
        let pixelSize = LayoutSize(width: 1000, height: 1250)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: [placement],
            defaultFrame: FramePreset.whiteMarginBlackBorder.photoFrame,
            pagePixelSize: pixelSize
        )

        let data = try await renderer.render(plan: plan, pixelSize: pixelSize, format: .jpeg(quality: 0.9))

        // JPEGマジックナンバー
        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]))
        // 実ピクセルサイズ（scale=1）
        let exported = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(exported.scale, 1)
        XCTAssertEqual(Int(exported.size.width), 1000)
        XCTAssertEqual(Int(exported.size.height), 1250)
    }

    func testExportRendersTextWithoutCrashing() async throws {
        let page = PageEntity(
            index: 0,
            aspect: AspectRatio(width: 4, height: 5),
            background: FramePreset.whiteMargin.background
        )
        var project = ProjectEntity(pages: [page])
        let textID = project.addTextItem(toPage: 0, content: "フィルムA / 2026-07-17")
        let pixelSize = LayoutSize(width: 400, height: 500)
        let plan = RenderPlanBuilder.build(
            page: page,
            placements: [],
            textItems: project.textItems(onPage: 0),
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: pixelSize
        )
        XCTAssertTrue(project.textItems.contains { $0.id == textID })

        let data = try await renderer.render(plan: plan, pixelSize: pixelSize, format: .jpeg(quality: 0.9))

        XCTAssertEqual(data.prefix(2), Data([0xFF, 0xD8]))
        let exported = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(Int(exported.size.width), 400)
        XCTAssertEqual(Int(exported.size.height), 500)
    }

    func testExportPageUseCaseEndToEnd() async throws {
        let photoRef = try await store.store(imageData: makeTestImageData(width: 3200, height: 2400))
        var project = ProjectEntity(
            pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))]
        )
        project.addPhoto(photoRef)

        final class SpyLibrarySaver: PhotoLibrarySaving, @unchecked Sendable {
            var saved: Data?
            func save(imageData: Data) async throws { saved = imageData }
        }
        let saver = SpyLibrarySaver()
        let result = try await ExportPageUseCase(renderer: renderer, librarySaver: saver)
            .execute(project: project, pageIndex: 0)

        // 1:1ページに自然配置（クロップなし）。出力は正方形・長辺4096以内・偶数
        XCTAssertEqual(result.pixelSize.width, result.pixelSize.height) // 1:1ページ→正方形
        XCTAssertLessThanOrEqual(result.pixelSize.width, 4096)
        XCTAssertEqual(Int(result.pixelSize.width) % 2, 0)
        let savedData = try XCTUnwrap(saver.saved)
        let exported = try XCTUnwrap(UIImage(data: savedData))
        XCTAssertEqual(Int(exported.size.width), Int(result.pixelSize.width))
    }
}
