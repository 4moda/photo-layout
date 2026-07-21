import Foundation
import Testing
@testable import PhotoLayoutCore

@Suite("TextItemEntity: エンティティ・mutation・undo/redo・RenderPlanBuilder")
struct TextItemTests {
    let photo = PhotoRef(fileName: "p.jpg", pixelWidth: 6000, pixelHeight: 4000)

    func makeProject(margins: Double = 0.05) -> ProjectEntity {
        ProjectEntity(
            pages: [PageEntity(
                index: 0,
                aspect: AspectRatio(width: 4, height: 5),
                background: CanvasBackgroundStyle(color: .white, margins: EdgeInsetsRatio(uniform: margins))
            )]
        )
    }

    // MARK: - エンティティ

    @Test("値型として id・pageIndex・sortIndex・content・位置・フォントサイズ比率・色を保持する")
    func entityHoldsAllFields() {
        let id = UUID()
        let item = TextItemEntity(
            id: id, pageIndex: 2, sortIndex: 3, content: "フィルムA",
            x: 0.2, y: 0.3, fontSizeRatio: 0.05, color: .white
        )
        #expect(item.id == id)
        #expect(item.pageIndex == 2)
        #expect(item.sortIndex == 3)
        #expect(item.content == "フィルムA")
        #expect(item.x == 0.2)
        #expect(item.y == 0.3)
        #expect(item.fontSizeRatio == 0.05)
        #expect(item.color == .white)
    }

    // MARK: - mutationヘルパ

    @Test("addTextItem: 既定文字列でページへ追加され、sortIndexは0から連番")
    func addTextItemAppends() {
        var project = makeProject()
        let id1 = project.addTextItem(toPage: 0)
        let id2 = project.addTextItem(toPage: 0)

        #expect(project.textItems.count == 2)
        #expect(project.textItems(onPage: 0).map(\.id) == [id1, id2])
        #expect(project.textItems.first { $0.id == id1 }?.sortIndex == 0)
        #expect(project.textItems.first { $0.id == id2 }?.sortIndex == 1)
        #expect(project.textItems.first { $0.id == id1 }?.content == "テキスト")
    }

    @Test("moveTextItem: 正規化位置が更新される")
    func moveTextItemUpdatesPosition() {
        var project = makeProject()
        let id = project.addTextItem(toPage: 0)
        project.moveTextItem(id: id, x: 0.6, y: 0.7)

        let moved = project.textItems.first { $0.id == id }
        #expect(moved?.x == 0.6)
        #expect(moved?.y == 0.7)
    }

    @Test("removeTextItem: 削除後sortIndexが0からの連番に詰め直される")
    func removeTextItemReindexes() {
        var project = makeProject()
        let id1 = project.addTextItem(toPage: 0, content: "A")
        let id2 = project.addTextItem(toPage: 0, content: "B")
        let id3 = project.addTextItem(toPage: 0, content: "C")

        project.removeTextItem(id: id2)

        #expect(project.textItems.count == 2)
        #expect(project.textItems.contains { $0.id == id2 } == false)
        let ordered = project.orderedTextItems
        #expect(ordered.map(\.id) == [id1, id3])
        #expect(ordered.map(\.sortIndex) == [0, 1])
    }

    @Test("removeTextItem: 存在しないidは何もしない")
    func removeTextItemNoOpForUnknownID() {
        var project = makeProject()
        project.addTextItem(toPage: 0)
        project.removeTextItem(id: UUID())
        #expect(project.textItems.count == 1)
    }

    @Test("ページ挿入/削除/並べ替えでtextItemのpageIndexが写真配置と同様に追随する")
    func pageStructureChangesKeepPageIndexInSync() {
        var project = makeProject()
        project.appendPage() // ページ1
        let id0 = project.addTextItem(toPage: 0)
        let id1 = project.addTextItem(toPage: 1)

        project.insertPage(at: 0) // 先頭挿入、既存ページは1つ後ろへ
        #expect(project.textItems.first { $0.id == id0 }?.pageIndex == 1)
        #expect(project.textItems.first { $0.id == id1 }?.pageIndex == 2)

        project.movePage(from: 1, to: 2)
        #expect(project.textItems.first { $0.id == id0 }?.pageIndex == 2)
        #expect(project.textItems.first { $0.id == id1 }?.pageIndex == 1)

        project.removePage(at: 0)
        #expect(project.textItems.first { $0.id == id0 }?.pageIndex == 1)
        #expect(project.textItems.first { $0.id == id1 }?.pageIndex == 0)
    }

    // MARK: - undo/redo

    @Test("追加・移動・削除がundo/redoで戻る/やり直せる")
    func undoRedoRoundTripsTextEdits() {
        var project = makeProject()
        var history = EditHistory()

        // 追加
        history.push(project)
        let id = project.addTextItem(toPage: 0, content: "テキスト")
        #expect(project.textItems.count == 1)

        // 移動
        history.push(project)
        project.moveTextItem(id: id, x: 0.5, y: 0.5)
        #expect(project.textItems.first?.x == 0.5)

        // 削除
        history.push(project)
        project.removeTextItem(id: id)
        #expect(project.textItems.isEmpty)

        // undo x3: 削除→移動→追加が順に戻る
        guard let afterUndoDelete = history.undo(current: project) else {
            Issue.record("undo(削除)がnil"); return
        }
        #expect(afterUndoDelete.textItems.count == 1)
        #expect(afterUndoDelete.textItems.first?.x == 0.5)

        guard let afterUndoMove = history.undo(current: afterUndoDelete) else {
            Issue.record("undo(移動)がnil"); return
        }
        #expect(afterUndoMove.textItems.count == 1)
        #expect(afterUndoMove.textItems.first?.x != 0.5)

        guard let afterUndoAdd = history.undo(current: afterUndoMove) else {
            Issue.record("undo(追加)がnil"); return
        }
        #expect(afterUndoAdd.textItems.isEmpty)

        // redo x3: 追加→移動→削除が順にやり直される
        guard let afterRedoAdd = history.redo(current: afterUndoAdd) else {
            Issue.record("redo(追加)がnil"); return
        }
        #expect(afterRedoAdd.textItems.count == 1)

        guard let afterRedoMove = history.redo(current: afterRedoAdd) else {
            Issue.record("redo(移動)がnil"); return
        }
        #expect(afterRedoMove.textItems.first?.x == 0.5)

        guard let afterRedoDelete = history.redo(current: afterRedoMove) else {
            Issue.record("redo(削除)がnil"); return
        }
        #expect(afterRedoDelete.textItems.isEmpty)
    }

    // MARK: - RenderPlanBuilder

    @Test("RenderPlanBuilder: テキストは写真・枠より後（最前面）にdrawTextとして生成される")
    func renderPlanBuilderAppendsTextAfterPhotoAndFrame() {
        var project = makeProject()
        project.defaultPhotoFrame = PhotoFrameStyle(borderColor: .black, borderWidthRatio: 0.01, cornerRadiusRatio: 0)
        project.addPhoto(photo)
        project.placeAllFillingPage()
        let textID = project.addTextItem(toPage: 0, content: "フィルムA")

        let commands = RenderPlanBuilder.build(
            page: project.orderedPages[0],
            placements: project.orderedPlacements,
            textItems: project.textItems(onPage: 0),
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: LayoutSize(width: 400, height: 500)
        )

        // [0]=背景, [1]=drawImage, [2]=strokeBorder, [3]=drawText
        #expect(commands.count == 4)
        guard case .drawText(let text, _, _, _, let color) = commands.last else {
            Issue.record("最後がdrawTextでない"); return
        }
        #expect(text == "フィルムA")
        #expect(color == project.textItems.first { $0.id == textID }?.color)
    }

    @Test("RenderPlanBuilder: 複数テキストはsortIndex順に生成される")
    func renderPlanBuilderOrdersTextBySortIndex() {
        var project = makeProject()
        project.addTextItem(toPage: 0, content: "1番目")
        project.addTextItem(toPage: 0, content: "2番目")

        let commands = RenderPlanBuilder.build(
            page: project.orderedPages[0],
            placements: [],
            textItems: project.textItems(onPage: 0),
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: LayoutSize(width: 400, height: 500)
        )

        let texts: [String] = commands.compactMap {
            if case .drawText(let text, _, _, _, _) = $0 { return text }
            return nil
        }
        #expect(texts == ["1番目", "2番目"])
    }

    @Test("RenderPlanBuilder: textItemsを省略すると何もdrawTextが生成されない（既定引数）")
    func renderPlanBuilderDefaultsToNoText() {
        let project = makeProject()
        let commands = RenderPlanBuilder.build(
            page: project.orderedPages[0],
            placements: [],
            defaultFrame: project.defaultPhotoFrame,
            pagePixelSize: LayoutSize(width: 400, height: 500)
        )
        #expect(commands.allSatisfy { if case .drawText = $0 { return false }; return true })
    }

    @Test("低解像度・高解像度で同じ比率のフォントサイズ・同じ相対位置になる（定量検証）")
    func fontSizeAndPositionScaleProportionally() {
        var project = makeProject()
        let id = project.addTextItem(toPage: 0, content: "撮影日")
        project.moveTextItem(id: id, x: 0.15, y: 0.82)

        let small = LayoutSize(width: 400, height: 500)
        let large = LayoutSize(width: 3276.8, height: 4096)

        func plan(_ size: LayoutSize) -> DrawCommand {
            let commands = RenderPlanBuilder.build(
                page: project.orderedPages[0],
                placements: [],
                textItems: project.textItems(onPage: 0),
                defaultFrame: project.defaultPhotoFrame,
                pagePixelSize: size
            )
            guard let command = commands.first(where: {
                if case .drawText = $0 { return true }; return false
            }) else {
                fatalError("drawTextが見つからない")
            }
            return command
        }

        guard case .drawText(_, let originXS, let originYS, let fontSizeS, _) = plan(small),
              case .drawText(_, let originXL, let originYL, let fontSizeL, _) = plan(large) else {
            Issue.record("drawTextの取得に失敗"); return
        }

        // フォントサイズ比率（出力短辺に対する比率）が両サイズで一致する
        let refS = small.referenceDimension
        let refL = large.referenceDimension
        #expect(abs(fontSizeS / refS - fontSizeL / refL) < 1e-9)

        // 配置領域に対する相対位置（原点からの割合）が両サイズで一致する
        let contentS = PageGeometry.contentRect(page: project.orderedPages[0], pageSize: small)
        let contentL = PageGeometry.contentRect(page: project.orderedPages[0], pageSize: large)
        let relXS = (originXS - contentS.x) / contentS.width
        let relYS = (originYS - contentS.y) / contentS.height
        let relXL = (originXL - contentL.x) / contentL.width
        let relYL = (originYL - contentL.y) / contentL.height
        #expect(abs(relXS - relXL) < 1e-9)
        #expect(abs(relYS - relYL) < 1e-9)
        #expect(abs(relXS - 0.15) < 1e-9)
        #expect(abs(relYS - 0.82) < 1e-9)
    }
}
