import Testing
@testable import PhotoLayoutCore

@Suite("SnapEngine")
struct SnapEngineTests {
    @Test("ページ中心線へ吸着し、縦ガイドが返る")
    func snapToPageCenter() {
        let moving = LayoutRect(x: 0.26, y: 0.3, width: 0.5, height: 0.2) // midX=0.51 ≈ 0.5
        let result = SnapEngine.snap(moving: moving)
        #expect(abs(result.rect.midX - 0.5) < 1e-12)
        #expect(result.guides.contains(SnapEngine.Guide(axis: .vertical, position: 0.5)))
    }

    @Test("しきい値を超えていれば吸着しない")
    func noSnapBeyondThreshold() {
        let moving = LayoutRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3)
        let result = SnapEngine.snap(moving: moving, threshold: 0.02)
        #expect(result.rect == moving)
        #expect(result.guides.isEmpty)
    }

    @Test("他の配置の辺へ吸着する（辺揃え）")
    func snapToOtherRectEdge() {
        let other = LayoutRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let moving = LayoutRect(x: 0.415, y: 0.6, width: 0.3, height: 0.3) // minX=0.415 ≈ other.maxX=0.4
        let result = SnapEngine.snap(moving: moving, others: [other])
        #expect(abs(result.rect.minX - 0.4) < 1e-12)
        #expect(result.guides.contains(SnapEngine.Guide(axis: .vertical, position: 0.4)))
    }

    @Test("X/Y軸は独立に吸着する")
    func independentAxes() {
        let moving = LayoutRect(x: 0.005, y: 0.3, width: 0.3, height: 0.3) // minX≈0のみ
        let result = SnapEngine.snap(moving: moving)
        #expect(result.rect.minX == 0)
        #expect(result.rect.y == 0.3)
        #expect(result.guides.count == 1)
    }
}
