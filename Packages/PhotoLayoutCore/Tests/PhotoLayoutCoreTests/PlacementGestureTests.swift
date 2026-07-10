import Testing
@testable import PhotoLayoutCore

@Suite("PlacementGesture")
struct PlacementGestureTests {
    let matted = LayoutRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    @Test("移動: はみ出しは許可しつつ最小の重なりでクランプされる")
    func moveClampsToMinVisible() {
        let result = PlacementGesture.move(
            destRect: matted, translationX: 10, translationY: -10, snapThreshold: 0
        )
        #expect(abs(result.rect.x - (1 - PlacementGesture.minVisible)) < 1e-12)
        #expect(abs(result.rect.y - (PlacementGesture.minVisible - matted.height)) < 1e-12)
    }

    @Test("移動: 全面配置の写真も動かせる（はみ出し＝クロップ調整になる）")
    func movingFullBleedOverflows() {
        let result = PlacementGesture.move(
            destRect: .unit, translationX: 0.2, translationY: 0, snapThreshold: 0
        )
        #expect(abs(result.rect.x - 0.2) < 1e-12)
        #expect(result.rect.width == 1)
    }

    @Test("移動: スナップなしでは平行移動、アスペクト不変")
    func movePreservesSize() {
        let result = PlacementGesture.move(
            destRect: matted, translationX: 0.1, translationY: 0.05, snapThreshold: 0
        )
        #expect(abs(result.rect.x - 0.35) < 1e-12)
        #expect(abs(result.rect.y - 0.3) < 1e-12)
        #expect(result.rect.width == matted.width)
        #expect(result.rect.height == matted.height)
    }

    @Test("拡縮: 中心固定・縦横同率（アスペクト固定）")
    func scaleKeepsCenterAndAspect() {
        let scaled = PlacementGesture.scale(destRect: matted, factor: 1.5)
        #expect(abs(scaled.midX - matted.midX) < 1e-12)
        #expect(abs(scaled.midY - matted.midY) < 1e-12)
        #expect(abs(scaled.width - 0.75) < 1e-12)
        #expect(abs(scaled.aspectRatio - matted.aspectRatio) < 1e-12)
    }

    @Test("拡縮: 最小・最大幅でクランプ（全面配置からの拡大＝クロップ詰めも可能）")
    func scaleClamps() {
        let tooSmall = PlacementGesture.scale(destRect: matted, factor: 0.01)
        #expect(abs(tooSmall.width - 0.05) < 1e-12)
        let tooBig = PlacementGesture.scale(destRect: matted, factor: 100)
        #expect(abs(tooBig.width - 4.0) < 1e-12)
        let fullBleedZoom = PlacementGesture.scale(destRect: .unit, factor: 1.5)
        #expect(abs(fullBleedZoom.width - 1.5) < 1e-12)
    }

    @Test("拡縮スナップ: 動く角がページ端に近いと端へ吸着しガイドを返す")
    func scaleAnchoredSnapsToEdge() {
        // topLeftアンカー（左上固定）。factor=1.48で右下角≒(0.99,0.99)→端(1.0)へ吸着
        let base = LayoutRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let result = PlacementGesture.scaleAnchoredSnapped(destRect: base, factor: 1.48, anchor: .topLeft)
        // 右下角のxが1.0へ吸着 → width=0.75, x固定0.25
        #expect(abs(result.rect.maxX - 1.0) < 1e-9)
        #expect(abs(result.rect.minX - 0.25) < 1e-12) // アンカー（左）は不動
        #expect(result.guides.contains { $0.axis == .vertical && abs($0.position - 1.0) < 1e-9 })
    }

    @Test("拡縮スナップ: 端から遠いと吸着せずガイドなし")
    func scaleAnchoredNoSnapWhenFar() {
        let base = LayoutRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let result = PlacementGesture.scaleAnchoredSnapped(destRect: base, factor: 1.1, anchor: .topLeft)
        #expect(result.guides.isEmpty)
        #expect(abs(result.rect.width - 0.55) < 1e-9) // 素の拡縮のまま
    }

    @Test("クロップパン: 画像とは逆方向へcropRectが動き、0..1でクランプ")
    func panCropMovesOppositeAndClamps() {
        let crop = LayoutRect(x: 0.2, y: 0, width: 0.5, height: 1)
        // 枠内で画像を右へ10%動かす → cropRectは左へ crop.width*0.1
        let panned = PlacementGesture.panCrop(cropRect: crop, translationX: 0.1, translationY: 0)
        #expect(abs(panned.x - (0.2 - 0.05)) < 1e-12)
        // 大きく動かしても範囲内
        let far = PlacementGesture.panCrop(cropRect: crop, translationX: -100, translationY: 0)
        #expect(abs(far.x - 0.5) < 1e-12) // 1 - width
    }

    @Test("クロップズーム: 中心固定・縦横同率でpxアスペクト不変、限界でクランプ")
    func zoomCropPreservesAspect() {
        let crop = LayoutRect(x: 0.25, y: 0.1, width: 0.5, height: 0.8)
        let zoomedIn = PlacementGesture.zoomCrop(cropRect: crop, factor: 2)
        #expect(abs(zoomedIn.width - 0.25) < 1e-12)
        #expect(abs(zoomedIn.height - 0.4) < 1e-12)   // 同率 → pxアスペクト不変
        #expect(abs(zoomedIn.midX - crop.midX) < 1e-12)

        // ズームアウトは元画像に収まる範囲まで（height=0.8が律速 → 1/0.8倍まで）
        let zoomedOut = PlacementGesture.zoomCrop(cropRect: crop, factor: 0.1)
        #expect(abs(zoomedOut.height - 1.0) < 1e-12)
        #expect(zoomedOut.minY >= 0)
        #expect(zoomedOut.maxY <= 1 + 1e-12)
    }
}
