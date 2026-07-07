import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("RenderPlanBuilder")
struct RenderPlanBuilderTests {
    // 4:5ページ、6000x4000横長写真（クロップなし）を全面配置
    let page = PageEntity(index: 0, aspect: AspectRatio(width: 4, height: 5),
                          background: CanvasBackgroundStyle(color: .white, margins: EdgeInsetsRatio(uniform: 0.05)))
    let photo = PhotoRef(fileName: "p.jpg", pixelWidth: 6000, pixelHeight: 4000)

    func makePlacement(mode: ContentMode) -> PlacementEntity {
        PlacementEntity(sortIndex: 0, photo: photo, contentMode: mode, destRect: .unit)
    }

    @Test("先頭は必ず背景塗り、ページ全面")
    func backgroundFirst() {
        let size = LayoutSize(width: 400, height: 500)
        let plan = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fit)],
                                           defaultFrame: .none, pagePixelSize: size)
        guard case .fillRect(let color, let rect) = plan.first else {
            Issue.record("先頭がfillRectでない"); return
        }
        #expect(color == .white)
        #expect(rect == LayoutRect(x: 0, y: 0, width: 400, height: 500))
    }

    @Test("fit: 横長写真は余白内で幅いっぱい・上下センタリング、元画像全体が写る")
    func fitLandscapePhoto() {
        let size = LayoutSize(width: 400, height: 500)
        let ref = 400.0 // min(400,500)
        let marginPx = 0.05 * ref // 20
        let plan = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fit)],
                                           defaultFrame: .none, pagePixelSize: size)
        guard case .drawImage(_, _, let source, let dest, _) = plan[1] else {
            Issue.record("2番目がdrawImageでない"); return
        }
        #expect(source == .unit) // fitはクロップ全体
        // コンテンツ領域: x=20..380 (幅360), y=20..480 (高さ460)
        #expect(abs(dest.width - 360) < 1e-9)
        #expect(abs(dest.height - 240) < 1e-9) // 360 / (6000/4000) = 240
        #expect(abs(dest.midY - 250) < 1e-9)   // 縦センタリング
    }

    @Test("fill: セルアスペクトに合わせsourceRectが中央で絞り込まれ、destはセル全面")
    func fillCropsSource() {
        let size = LayoutSize(width: 400, height: 500)
        let plan = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fill)],
                                           defaultFrame: .none, pagePixelSize: size)
        guard case .drawImage(_, _, let source, let dest, _) = plan[1] else {
            Issue.record("2番目がdrawImageでない"); return
        }
        // セル: 360x460 → aspect 360/460。元画像6000x4000。
        // 必要な元画像内の幅(px) = 4000 * (360/460) = 3130.43…px → 正規化幅 = /6000
        let cellAspect = 360.0 / 460.0
        let expectedWidthNorm = (4000.0 * cellAspect) / 6000.0
        #expect(abs(source.width - expectedWidthNorm) < 1e-9)
        #expect(abs(source.height - 1.0) < 1e-9)
        #expect(abs(source.midX - 0.5) < 1e-9) // 中央絞り込み
        #expect(abs(dest.width - 360) < 1e-9)
        #expect(abs(dest.height - 460) < 1e-9)
    }

    @Test("枠線: 太さ比率がpx化され、画像内側に半分insetされる")
    func borderInset() {
        let size = LayoutSize(width: 400, height: 500)
        let frame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.01, cornerRadiusRatio: 0)
        let plan = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fill)],
                                           defaultFrame: frame, pagePixelSize: size)
        guard case .strokeBorder(let color, let widthPx, _, let rect) = plan[2] else {
            Issue.record("3番目がstrokeBorderでない"); return
        }
        #expect(color == .black)
        #expect(abs(widthPx - 4) < 1e-9) // 0.01 * 400
        // 画像セル(20,20,360,460)から半幅(2px)内側
        #expect(abs(rect.x - 22) < 1e-9)
        #expect(abs(rect.width - 356) < 1e-9)
    }

    @Test("プレビュー(400px)と書き出し(4096px)で全ジオメトリが相似（比率一致）")
    func previewExportProportionality() {
        let small = LayoutSize(width: 400, height: 500)
        let large = LayoutSize(width: 3276.8, height: 4096)
        let frame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.008, cornerRadiusRatio: 0.02)
        let planS = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fill)],
                                            defaultFrame: frame, pagePixelSize: small)
        let planL = RenderPlanBuilder.build(page: page, placements: [makePlacement(mode: .fill)],
                                            defaultFrame: frame, pagePixelSize: large)
        let scale = large.width / small.width // 8.192

        #expect(planS.count == planL.count)
        for (s, l) in zip(planS, planL) {
            switch (s, l) {
            case (.fillRect(_, let rs), .fillRect(_, let rl)):
                expectScaled(rs, rl, scale: scale)
            case (.drawImage(_, _, let srcS, let destS, let crS),
                  .drawImage(_, _, let srcL, let destL, let crL)):
                #expect(srcS == srcL) // sourceは正規化なので完全一致
                expectScaled(destS, destL, scale: scale)
                #expect(abs(crS * scale - crL) < 1e-6)
            case (.strokeBorder(_, let wS, let crS, let rS),
                  .strokeBorder(_, let wL, let crL, let rL)):
                #expect(abs(wS * scale - wL) < 1e-6)
                #expect(abs(crS * scale - crL) < 1e-6)
                expectScaled(rS, rL, scale: scale)
            default:
                Issue.record("コマンド種別がプレビューと書き出しで不一致")
            }
        }
    }

    private func expectScaled(_ small: LayoutRect, _ large: LayoutRect, scale: Double) {
        #expect(abs(small.x * scale - large.x) < 1e-6)
        #expect(abs(small.y * scale - large.y) < 1e-6)
        #expect(abs(small.width * scale - large.width) < 1e-6)
        #expect(abs(small.height * scale - large.height) < 1e-6)
    }
}
