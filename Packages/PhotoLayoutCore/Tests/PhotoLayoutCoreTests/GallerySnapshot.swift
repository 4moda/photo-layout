import Foundation
import Testing
@testable import PhotoLayoutCore

/// 操作シナリオ→描画結果の「ギャラリー」を JSON で書き出す（Linuxで完結・CI不要）。
///
/// `RenderPlanBuilder` の [DrawCommand] はプレビューも書き出しも同一なので、ここで出す描画は
/// 「編集画面のキャンバス」であり「書き出し結果」でもある。JSON を Python(PIL)でPNG化して確認する。
///
/// 使い方: `GALLERY_OUT=/path/commands.json swift test --filter generateGallery`
/// 環境変数が無ければ何もしない（通常のテスト実行を汚さない）。
@Suite("ギャラリー生成")
struct GallerySnapshotTests {
    @Test("operationシナリオを描画命令JSONへ書き出す")
    func generateGallery() throws {
        guard let out = ProcessInfo.processInfo.environment["GALLERY_OUT"] else { return }
        let scenarios = GalleryScenarios.all()
        let dto = scenarios.map { ScenarioDTO(from: $0) }
        let data = try JSONEncoder().encode(dto)
        try data.write(to: URL(fileURLWithPath: out))
    }
}

// MARK: - シナリオ定義（操作＝Coreミューテーション）

enum GalleryScenarios {
    struct Scenario {
        let name: String
        let note: String
        let project: ProjectEntity
    }

    static let wide = PhotoRef(fileName: "wide.jpg", pixelWidth: 4000, pixelHeight: 3000)   // 4:3
    static let tall = PhotoRef(fileName: "tall.jpg", pixelWidth: 3000, pixelHeight: 4000)   // 3:4
    static let pano = PhotoRef(fileName: "pano.jpg", pixelWidth: 6000, pixelHeight: 2000)   // 3:1
    static let sq = PhotoRef(fileName: "square.jpg", pixelWidth: 3000, pixelHeight: 3000)   // 1:1

    static func page(_ w: Double, _ h: Double, bg: CanvasBackgroundStyle = .plainWhite) -> ProjectEntity {
        ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: w, height: h), background: bg)])
    }

    static func all() -> [Scenario] {
        var out: [Scenario] = []

        // 写真追加（自然配置・元アスペクトのまま中央付近）
        do {
            var p = page(4, 5)
            p.addPhoto(wide)
            out.append(.init(name: "写真1枚・自然配置", note: "元アスペクトのまま中央付近（クロップなし）", project: p))
        }
        // 複数追加（カスケードで少しずつずれる）
        do {
            var p = page(1, 1)
            p.addPhoto(wide); p.addPhoto(tall); p.addPhoto(sq)
            out.append(.init(name: "写真3枚・カスケード", note: "完全に重ならないよう少しずつずれる", project: p))
        }
        // 全面配置
        do {
            var p = page(4, 5); p.addPhoto(wide); p.placeAllFillingPage()
            out.append(.init(name: "全面配置", note: "配置領域いっぱい（はみ出しはクロップ）", project: p))
        }
        // マット配置
        do {
            var p = page(1, 1); p.addPhoto(wide); p.placeAllMatted(coverage: 0.8)
            out.append(.init(name: "マット配置80%", note: "写真全体＋余白で中央", project: p))
        }
        // テンプレ田の字（空スロット）
        do {
            var p = page(1, 1); p.applyTemplate(LayoutTemplateTable.fourUp()[0], toPage: 0)
            out.append(.init(name: "テンプレ田の字・空", note: "型枠を敷いた直後（スロットは点線）", project: p))
        }
        // テンプレ田の字（4枚充填）
        do {
            var p = page(1, 1)
            p.applyTemplate(LayoutTemplateTable.fourUp()[0], toPage: 0)
            for i in 0..<4 { p.assignPhoto([wide, tall, sq, pano][i], toPage: 0, slot: i) }
            out.append(.init(name: "テンプレ田の字・4枚", note: "各スロットへ当てはめ（中央クロップ）", project: p))
        }
        // 左大＋右2（3枚）
        do {
            var p = page(1, 1)
            p.applyTemplate(LayoutTemplateTable.threeUp()[0], toPage: 0)
            for i in 0..<3 { p.assignPhoto([wide, tall, sq][i], toPage: 0, slot: i) }
            out.append(.init(name: "テンプレ左大＋右2", note: "3枚レイアウト", project: p))
        }
        // 背景 黒
        do {
            var p = page(1, 1); p.addPhoto(wide); p.placeAllMatted(coverage: 0.8)
            p.setAllPagesBackgroundColor(.black)
            out.append(.init(name: "背景 黒", note: "プロジェクト共通の背景色", project: p))
        }
        // 枠 白フチ
        do {
            var p = page(1, 1); p.addPhoto(wide); p.placeAllMatted(coverage: 0.8)
            p.setAllPagesBackgroundColor(.black)
            if let id = p.placements.first?.id {
                p.setPlacementFrame(PhotoFrameStyle(borderColor: .white, borderWidthRatio: 0.012, cornerRadiusRatio: 0), placementID: id)
            }
            out.append(.init(name: "枠 白フチ", note: "写真の縁（黒背景＋白フチ）", project: p))
        }
        // パノラマ3連・跨ぎ（1枚が全スライドへ）
        do {
            var p = ProjectEntity(pages: (0..<3).map { PageEntity(index: $0, aspect: AspectRatio(width: 1, height: 1)) })
            p.addPhoto(pano)
            if let id = p.placements.first?.id { p.placeSpanningAllSlides(placementID: id) }
            out.append(.init(name: "パノラマ3連・跨ぎ", note: "1枚が3スライドにまたがる（各スライドにスライス）", project: p))
        }
        // 分割（1枚→3スライド）
        do {
            var p = ProjectEntity(pages: [PageEntity(index: 0, aspect: AspectRatio(width: 1, height: 1))])
            p.splitPhoto(pano, intoSlides: 3, slideAspect: AspectRatio(width: 4, height: 5))
            out.append(.init(name: "分割 3スライド", note: "1枚をN枚のスライドへスライス", project: p))
        }
        return out
    }
}

// MARK: - JSON DTO（描画命令＝書き出しと同一）

private let renderHeight: Double = 360

struct CmdDTO: Codable {
    let type: String            // "fill" | "image" | "border" | "slot"
    let rect: [Double]          // x,y,w,h (px)
    var color: [Double]? = nil  // r,g,b,a
    var lineWidth: Double? = nil
    var cornerRadius: Double? = nil
    var photo: String? = nil
    var sourceRect: [Double]? = nil  // x,y,w,h (元画像0..1)
}

struct PageDTO: Codable {
    let width: Double
    let height: Double
    let commands: [CmdDTO]
}

struct ScenarioDTO: Codable {
    let name: String
    let note: String
    let pages: [PageDTO]

    init(from s: GalleryScenarios.Scenario) {
        self.name = s.name
        self.note = s.note
        self.pages = s.project.orderedPages.map { page in
            let size = LayoutSize(width: page.aspect.ratio * renderHeight, height: renderHeight)
            let visible = SpreadGeometry.visiblePlacements(onPage: page.index, project: s.project)
            let plan = RenderPlanBuilder.build(
                page: page, placements: visible, defaultFrame: s.project.defaultPhotoFrame, pagePixelSize: size)
            var cmds = plan.map(CmdDTO.init(command:))
            // 空スロットの範囲だけ描く（充填済みは画像が見えるよう描かない）。ギャラリー専用の補助
            if let slots = page.slots {
                let content = PageGeometry.contentRect(page: page, pageSize: size)
                let empties = Set(s.project.emptySlotIndices(onPage: page.index))
                for (i, slot) in slots.enumerated() where empties.contains(i) {
                    let r = PageGeometry.imageRect(destRect: slot, in: content)
                    cmds.append(CmdDTO(type: "slot", rect: [r.x, r.y, r.width, r.height]))
                }
            }
            return PageDTO(width: size.width, height: size.height, commands: cmds)
        }
    }
}

private extension CmdDTO {
    init(command: DrawCommand) {
        switch command {
        case let .fillRect(color, rect):
            self.init(type: "fill", rect: [rect.x, rect.y, rect.width, rect.height],
                      color: [color.red, color.green, color.blue, color.alpha])
        case let .drawImage(_, photo, sourceRect, destRect, cornerRadiusPx):
            self.init(type: "image", rect: [destRect.x, destRect.y, destRect.width, destRect.height],
                      cornerRadius: cornerRadiusPx, photo: photo.fileName,
                      sourceRect: [sourceRect.x, sourceRect.y, sourceRect.width, sourceRect.height])
        case let .strokeBorder(color, lineWidthPx, cornerRadiusPx, rect):
            self.init(type: "border", rect: [rect.x, rect.y, rect.width, rect.height],
                      color: [color.red, color.green, color.blue, color.alpha],
                      lineWidth: lineWidthPx, cornerRadius: cornerRadiusPx)
        }
    }
}
