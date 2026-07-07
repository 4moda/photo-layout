import Testing
@testable import PhotoLayoutCore

@Suite("ExportSizeCalculator")
struct ExportSizeCalculatorTests {
    @Test("元画像の実解像度を基準にページサイズが決まる（クロップなし全面配置）")
    func nativeResolutionDriven() {
        // 4:5ページに4000x5000写真を全面配置 → 4000x5000がそのまま必要…だが長辺4096へクランプ
        let page = PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5))
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "p.jpg", pixelWidth: 4000, pixelHeight: 5000),
            destRect: .unit
        )
        let size = ExportSizeCalculator.pageSize(page: page, placements: [placement])
        #expect(size.height == 4096)
        #expect(abs(size.width - 4096 * 0.8) < 2) // 偶数丸め誤差許容
    }

    @Test("低解像度写真ではクランプされず実解像度が使われる")
    func smallPhotoNoClamp() {
        let page = PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "p.jpg", pixelWidth: 2000, pixelHeight: 1500),
            cropRect: LayoutRect(x: 0, y: 0, width: 1, height: 0.8), // 高さ1200px分
            destRect: .unit
        )
        let size = ExportSizeCalculator.pageSize(page: page, placements: [placement])
        #expect(size.height == 1200)
        #expect(size.width == 1200)
    }

    @Test("写真なしはfallback（短辺2048）")
    func fallbackWithoutPhotos() {
        let portrait = PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5))
        let size = ExportSizeCalculator.pageSize(page: portrait, placements: [])
        #expect(size.width == 2048)
        #expect(size.height == 2560)

        let landscape = PageEntity(index: 0, aspect: AspectRatio(width: 16, height: 9))
        let sizeL = ExportSizeCalculator.pageSize(page: landscape, placements: [])
        #expect(sizeL.height == 2048)
    }

    @Test("出力サイズは常に偶数px")
    func evenPixels() {
        let page = PageEntity(index: 0, aspect: AspectRatio(width: 3, height: 4))
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "p.jpg", pixelWidth: 3001, pixelHeight: 4001),
            destRect: .unit
        )
        let size = ExportSizeCalculator.pageSize(page: page, placements: [placement])
        #expect(Int(size.width) % 2 == 0)
        #expect(Int(size.height) % 2 == 0)
    }
}
