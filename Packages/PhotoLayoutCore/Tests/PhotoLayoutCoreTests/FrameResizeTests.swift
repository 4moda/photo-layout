import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("角アンカー拡縮と辺ストレッチ")
struct AnchoredScaleTests {
    let rect = LayoutRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    @Test("scaleAnchored: アンカー角が不動でアスペクト固定")
    func anchorStaysFixed() {
        let scaled = PlacementGesture.scaleAnchored(destRect: rect, factor: 1.5, anchor: .topLeft)
        #expect(abs(scaled.minX - rect.minX) < 1e-12)
        #expect(abs(scaled.minY - rect.minY) < 1e-12)
        #expect(abs(scaled.width - 0.6) < 1e-12)
        #expect(abs(scaled.aspectRatio - rect.aspectRatio) < 1e-12)

        let fromBottomRight = PlacementGesture.scaleAnchored(destRect: rect, factor: 0.5, anchor: .bottomRight)
        #expect(abs(fromBottomRight.maxX - rect.maxX) < 1e-12)
        #expect(abs(fromBottomRight.maxY - rect.maxY) < 1e-12)
        #expect(abs(fromBottomRight.width - 0.2) < 1e-12)
    }

    @Test("Corner.opposite: 掴んだ角の対角が返る")
    func oppositeCorners() {
        #expect(PlacementGesture.Corner.topLeft.opposite == .bottomRight)
        #expect(PlacementGesture.Corner.bottomLeft.opposite == .topRight)
    }

    @Test("stretchEdge: 触った辺だけが動き反対辺は固定")
    func stretchMovesOnlyTargetEdge() {
        let wider = PlacementGesture.stretchEdge(destRect: rect, edge: .trailing, delta: 0.2)
        #expect(abs(wider.minX - rect.minX) < 1e-12)
        #expect(abs(wider.width - 0.6) < 1e-12)
        #expect(abs(wider.height - rect.height) < 1e-12)

        let fromLeading = PlacementGesture.stretchEdge(destRect: rect, edge: .leading, delta: -0.1)
        #expect(abs(fromLeading.maxX - rect.maxX) < 1e-12)
        #expect(abs(fromLeading.width - 0.5) < 1e-12)

        let taller = PlacementGesture.stretchEdge(destRect: rect, edge: .top, delta: -0.1)
        #expect(abs(taller.maxY - rect.maxY) < 1e-12)
        #expect(abs(taller.height - 0.5) < 1e-12)
    }

    @Test("stretchEdge: 最小サイズ未満には潰れない")
    func stretchClampsMinSize() {
        let squashed = PlacementGesture.stretchEdge(destRect: rect, edge: .trailing, delta: -10)
        #expect(abs(squashed.width - 0.05) < 1e-12)
    }
}

@Suite("枠アスペクト変更（画像は歪まない）")
struct FrameResizeTests {
    private func makeProject() -> (ProjectEntity, UUID) {
        var project = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
        let placement = PlacementEntity(
            sortIndex: 0,
            photo: PhotoRef(fileName: "a.jpg", pixelWidth: 3000, pixelHeight: 2000),
            cropRect: .unit,
            destRect: LayoutRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        project.placements = [placement]
        return (project, placement.id)
    }

    /// cropRectの実ピクセルアスペクト
    private func cropPixelAspect(_ p: PlacementEntity) -> Double {
        (p.cropRect.width * Double(p.photo.pixelWidth)) / (p.cropRect.height * Double(p.photo.pixelHeight))
    }

    /// destRectの実ピクセルアスペクト（1:1ページ・余白なし → contentAspect==1）
    private func destPixelAspect(_ p: PlacementEntity) -> Double {
        p.destRect.aspectRatio
    }

    @Test("resizeFrame: 枠変更後も不変条件（destのpxアスペクト==cropのpxアスペクト）が保たれる")
    func invariantHolds() {
        var (project, id) = makeProject()
        let newRect = LayoutRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4) // 横長の枠へ
        project.resizeFrame(placementID: id, to: newRect, recroppingFrom: .unit)
        let p = project.placements[0]
        #expect(p.destRect.isApproximatelyEqual(to: newRect))
        #expect(abs(destPixelAspect(p) - cropPixelAspect(p)) < 1e-9)
        // クロップは元画像の範囲内
        #expect(LayoutRect.unit.contains(p.cropRect))
    }

    @Test("setFramePixelAspect: 中心と幅を保ったまま枠のpxアスペクトが変わる")
    func setAspectKeepsCenterAndWidth() {
        var (project, id) = makeProject()
        let before = project.placements[0].destRect
        project.setFramePixelAspect(1.0, placementID: id) // 正方形の枠
        let p = project.placements[0]
        #expect(abs(p.destRect.midX - before.midX) < 1e-12)
        #expect(abs(p.destRect.midY - before.midY) < 1e-12)
        #expect(abs(p.destRect.width - before.width) < 1e-12)
        #expect(abs(destPixelAspect(p) - 1.0) < 1e-9)
        #expect(abs(cropPixelAspect(p) - 1.0) < 1e-9)
    }

    @Test("再クロップの基準（baseCrop）から絞られる — ドラッグ中の単調縮小を防ぐ設計")
    func recropUsesBase() {
        var (project, id) = makeProject()
        let base = LayoutRect(x: 0.25, y: 0, width: 0.5, height: 1) // ユーザーが左右をクロップ済み
        project.placements[0].cropRect = base
        // 枠を縦長へ → baseからさらに横を絞る（縦は据え置き）
        project.resizeFrame(
            placementID: id,
            to: LayoutRect(x: 0.3, y: 0.1, width: 0.3, height: 0.8),
            recroppingFrom: base
        )
        let crop = project.placements[0].cropRect
        #expect(base.contains(crop))
        #expect(abs(crop.height - base.height) < 1e-9)
    }
}
