import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("RenderPlanBuilder + 配置ヘルパ")
struct RenderPlanBuilderTests {
    // 4:5ページ・白余白(0.05)・6000x4000横長写真
    let photo = PhotoRef(fileName: "p.jpg", pixelWidth: 6000, pixelHeight: 4000)

    func makeProject(margins: Double = 0.05) -> ProjectEntity {
        var project = ProjectEntity(
            pages: [PageEntity(
                index: 0,
                aspect: AspectRatio(width: 4, height: 5),
                background: CanvasBackgroundStyle(color: .white, margins: EdgeInsetsRatio(uniform: margins))
            )]
        )
        project.addPhoto(photo) // 既定で全面配置
        return project
    }

    func plan(_ project: ProjectEntity, size: LayoutSize) -> [DrawCommand] {
        RenderPlanBuilder.build(
            page: project.orderedPages[0],
            placements: project.orderedPlacements,
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: size
        )
    }

    @Test("先頭は必ず背景塗り、ページ全面")
    func backgroundFirst() {
        let commands = plan(makeProject(), size: LayoutSize(width: 400, height: 500))
        guard case .fillRect(let color, let rect) = commands.first else {
            Issue.record("先頭がfillRectでない"); return
        }
        #expect(color == .white)
        #expect(rect == LayoutRect(x: 0, y: 0, width: 400, height: 500))
    }

    @Test("全面配置: クロップが配置領域アスペクトへ絞られ、表示矩形は配置領域全面")
    func fillPlacement() {
        let project = makeProject()
        // 配置領域: 名目w=0.8,h=1, ref=0.8, 余白0.04ずつ → 0.72x0.92 → aspect≈0.782609
        let contentAspect = project.orderedPages[0].contentAspect
        #expect(abs(contentAspect - 0.72 / 0.92) < 1e-9)

        let commands = plan(project, size: LayoutSize(width: 400, height: 500))
        guard case .drawImage(_, _, let source, let dest, _) = commands[1] else {
            Issue.record("2番目がdrawImageでない"); return
        }
        // 横長写真(1.5)を縦長領域(0.7826)へ → 幅が絞られる: (4000*0.7826..)/6000
        let expectedWidth = (4000.0 * contentAspect) / 6000.0
        #expect(abs(source.width - expectedWidth) < 1e-9)
        #expect(abs(source.midX - 0.5) < 1e-9)
        // 表示矩形は配置領域全面（余白20px）
        #expect(abs(dest.x - 20) < 1e-9)
        #expect(abs(dest.width - 360) < 1e-9)
        #expect(abs(dest.height - 460) < 1e-9)
    }

    @Test("マット配置: 写真全体が写り、余白を残して中央、アスペクト不変条件を満たす")
    func mattedPlacement() {
        var project = makeProject()
        project.placeAllMatted(coverage: 0.9)

        let commands = plan(project, size: LayoutSize(width: 400, height: 500))
        guard case .drawImage(_, _, let source, let dest, _) = commands[1] else {
            Issue.record("2番目がdrawImageでない"); return
        }
        // クロップは全体（防御的正規化でもほぼunitのまま）
        #expect(source.isApproximatelyEqual(to: .unit, tolerance: 1e-6))
        // 表示矩形のピクセルアスペクト == 写真のアスペクト（角ドラッグ拡縮の固定対象）
        #expect(abs(dest.aspectRatio - 1.5) < 1e-6)
        // 中央配置・coverage 0.9 → 幅 = 360*0.9 = 324
        #expect(abs(dest.width - 324) < 1e-6)
        #expect(abs(dest.midX - 200) < 1e-6)   // ページ中央
        #expect(abs(dest.midY - 250) < 1e-6)
    }

    @Test("枠線: 太さ比率がpx化され、写真の内側に半分insetされる")
    func borderInset() {
        var project = makeProject()
        project.defaultPhotoFrame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.01, cornerRadiusRatio: 0)

        let commands = plan(project, size: LayoutSize(width: 400, height: 500))
        guard case .strokeBorder(let color, let widthPx, _, let rect) = commands[2] else {
            Issue.record("3番目がstrokeBorderでない"); return
        }
        #expect(color == .black)
        #expect(abs(widthPx - 4) < 1e-9) // 0.01 * 400
        // 写真表示矩形(20,20,360,460)から半幅(2px)内側
        #expect(abs(rect.x - 22) < 1e-9)
        #expect(abs(rect.width - 356) < 1e-9)
    }

    @Test("マット配置でも枠は写真自体に付く")
    func borderFollowsPhotoWhenMatted() {
        var project = makeProject()
        project.defaultPhotoFrame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.01, cornerRadiusRatio: 0)
        project.placeAllMatted(coverage: 0.9)

        let commands = plan(project, size: LayoutSize(width: 400, height: 500))
        guard case .drawImage(_, _, _, let dest, _) = commands[1],
              case .strokeBorder(_, _, _, let borderRect) = commands[2] else {
            Issue.record("コマンド構成が想定外"); return
        }
        // 枠は写真の表示矩形（マットで縮んだ矩形）を囲む
        #expect(abs(borderRect.x - (dest.x + 2)) < 1e-6)
        #expect(abs(borderRect.width - (dest.width - 4)) < 1e-6)
    }

    @Test("プレビュー(400px)と書き出し(4096px)で全ジオメトリが相似（比率一致）")
    func previewExportProportionality() {
        var project = makeProject()
        project.defaultPhotoFrame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.008, cornerRadiusRatio: 0.02)

        let small = LayoutSize(width: 400, height: 500)
        let large = LayoutSize(width: 3276.8, height: 4096)
        let planS = plan(project, size: small)
        let planL = plan(project, size: large)
        let scale = large.width / small.width

        #expect(planS.count == planL.count)
        for (s, l) in zip(planS, planL) {
            switch (s, l) {
            case (.fillRect(_, let rs), .fillRect(_, let rl)):
                expectScaled(rs, rl, scale: scale)
            case (.drawImage(_, _, let srcS, let destS, let crS),
                  .drawImage(_, _, let srcL, let destL, let crL)):
                #expect(srcS.isApproximatelyEqual(to: srcL))
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

    @Test("アスペクト変更で全面/マットの配置意図が保たれ、不変条件が維持される")
    func aspectChangeReplaces() {
        var filled = makeProject()
        filled.setPageAspect(AspectRatio(width: 16, height: 9))
        #expect(filled.placements[0].destRect.isApproximatelyEqual(to: .unit))
        // 16:9(1.777) > 写真1.5 → 高さが絞られる
        #expect(filled.placements[0].cropRect.height < 1)

        var matted = makeProject()
        matted.placeAllMatted(coverage: 0.9)
        matted.setPageAspect(AspectRatio(width: 1, height: 1))
        let placement = matted.placements[0]
        #expect(placement.cropRect.isApproximatelyEqual(to: .unit))
        // 不変条件: destRectのpxアスペクト == 写真アスペクト
        let page = matted.orderedPages[0]
        let destPixelAspect = placement.destRect.aspectRatio * page.contentAspect
        #expect(abs(destPixelAspect - 1.5) < 1e-6)
    }

    private func expectScaled(_ small: LayoutRect, _ large: LayoutRect, scale: Double) {
        #expect(abs(small.x * scale - large.x) < 1e-6)
        #expect(abs(small.y * scale - large.y) < 1e-6)
        #expect(abs(small.width * scale - large.width) < 1e-6)
        #expect(abs(small.height * scale - large.height) < 1e-6)
    }
}
