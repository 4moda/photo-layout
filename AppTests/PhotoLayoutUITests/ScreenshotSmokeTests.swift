import XCTest

/// 主要画面を巡回してスクリーンショットをXCTAttachmentとして保存するスモークテスト。
/// CIがxcresultからPNGを抽出しartifact化する — Macを持たない開発者が
/// 「実際の画面」を確認する唯一の手段なので、画面を追加したらここにも撮影を追加すること。
final class ScreenshotSmokeTests: XCTestCase {
    @MainActor
    func testProjectListCreateFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let navTitle = app.navigationBars["PhotoLayout"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 15))
        attachScreenshot(named: "01-project-list")

        // ＋メニュー → 用紙サイズ（正方形）を選ぶ → 作成後は自動でエディタへ遷移する
        // SwiftUIのツールバーMenuは.tap()がkAXErrorCannotCompleteになることがあるため座標タップ
        let addButton = app.buttons["projectList.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let squareButton = app.buttons["projectList.new_square"]
        XCTAssertTrue(squareButton.waitForExistence(timeout: 5))
        attachScreenshot(named: "02-new-project-menu")
        squareButton.tap()

        let exportButton = app.buttons["pageEditor.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 10))
        attachScreenshot(named: "02b-editor-empty-state")

        // ページ俯瞰モード → ページを追加 → 完了で連結キャンバスへ
        app.buttons["pageEditor.overview"].tap()
        let appendButton = app.buttons["overview.append"]
        XCTAssertTrue(appendButton.waitForExistence(timeout: 5))
        attachScreenshot(named: "02c-page-overview")
        appendButton.tap()
        sleep(1)
        app.buttons["overview.done"].tap()

        // 2ページが隙間なく並ぶシームレスキャンバス
        let pageLabel = app.staticTexts["pageEditor.pageLabel"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 5))
        sleep(1)
        attachScreenshot(named: "02d-seamless-two-pages")

        // 一覧へ戻ると下書きが増えている（グリッドのセルは名前をidentifierに持つ）
        app.navigationBars.buttons.firstMatch.tap()
        let row = app.buttons["無題のレイアウト"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSlotTemplateFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 正方形プロジェクトを新規作成 → エディタへ
        let addButton = app.buttons["projectList.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let squareButton = app.buttons["projectList.new_square"]
        XCTAssertTrue(squareButton.waitForExistence(timeout: 5))
        squareButton.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 10))

        // テンプレ（田の字）を敷くと空スロット（＋）が現れる＝スロット先行
        let templateMenu = app.buttons["pageEditor.templateMenu"]
        XCTAssertTrue(templateMenu.waitForExistence(timeout: 5))
        templateMenu.tap()
        let grid = app.buttons["田の字"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        sleep(1)
        attachScreenshot(named: "07-template-empty-slots")
    }

    @MainActor
    func testPageEditorWithDemoPhoto() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        // デモプロジェクト（生成写真1枚・白余白プリセット入り）を開く
        let demoRow = app.buttons["デモ"]
        XCTAssertTrue(demoRow.waitForExistence(timeout: 15))
        demoRow.tap()

        // エディタ到達の確認はツールバーの書き出しボタンで行う（Canvasは要素階層に出ないことがある）
        let exportButton = app.buttons["pageEditor.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15))
        sleep(2) // プレビュー画像の非同期ロードを待つ
        attachScreenshot(named: "03-editor-photo")

        // キャンバス中央をタップ→写真が選択され、写真メニュー（削除・クロップ等）に切り替わる
        let canvas = app.otherElements["pageEditor.canvas"].firstMatch
        if canvas.exists {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let deleteButton = app.buttons["pageEditor.deletePhoto"]
            if deleteButton.waitForExistence(timeout: 5) {
                attachScreenshot(named: "05b-photo-selected-menu")
            }
        }
    }

    @MainActor
    func testSpanningPhotoAcrossSlides() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        // 1枚が3スライドにまたがるデモ（プロジェクト配置モデル）を開く
        let row = app.buttons["パノラマ（3連）"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2) // プレビュー画像の非同期ロードを待つ
        attachScreenshot(named: "08-spanning-carousel")
    }

    @MainActor
    func testCollageAndFramedDemos() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        // コラージュ（田の字4枚）: スロット合成の見た目
        let collage = app.buttons["コラージュ（4枚）"]
        XCTAssertTrue(collage.waitForExistence(timeout: 15))
        collage.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)
        attachScreenshot(named: "09-collage-template")

        app.navigationBars.buttons.firstMatch.tap() // 一覧へ戻る

        // 枠付き（黒背景＋白フチ・マット）
        let framed = app.buttons["枠付き（黒背景）"]
        XCTAssertTrue(framed.waitForExistence(timeout: 15))
        framed.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)
        attachScreenshot(named: "10-framed-black")
    }

    @MainActor
    func testEditorSheetsAndPreview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        let demoRow = app.buttons["デモ"]
        XCTAssertTrue(demoRow.waitForExistence(timeout: 15))
        demoRow.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)

        // テンプレート選択シート（型枠をビジュアル表示）
        app.buttons["pageEditor.templateMenu"].tap()
        if app.buttons["田の字"].waitForExistence(timeout: 5) {
            attachScreenshot(named: "11-template-sheet")
        }
        tapClose(app)

        // レイヤー順シート
        if app.buttons["pageEditor.layerButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.layerButton"].tap()
            sleep(1)
            attachScreenshot(named: "12-layer-sheet")
            tapClose(app)
        }

        // 書き出しプレビュー画面
        let export = app.buttons["pageEditor.export"]
        if export.isEnabled {
            export.tap()
            if app.buttons["preview.save"].waitForExistence(timeout: 5) {
                attachScreenshot(named: "13-preview")
            }
            tapClose(app)
        }

        // 写真を選択 → 枠（縁）シート
        let canvas = app.otherElements["pageEditor.canvas"].firstMatch
        if canvas.exists {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if app.buttons["pageEditor.frameButton"].waitForExistence(timeout: 5) {
                app.buttons["pageEditor.frameButton"].tap()
                if app.buttons["白フチ"].waitForExistence(timeout: 5) {
                    attachScreenshot(named: "14-frame-sheet")
                }
                tapClose(app)
            }
        }
    }

    /// シート/プレビューの「閉じる」を押す（存在すれば）
    @MainActor
    private func tapClose(_ app: XCUIApplication) {
        let close = app.buttons["閉じる"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        sleep(1)
    }

    @MainActor
    func testXPostTimelineComposite() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        // X 3枚デモ（左大＋右2段のタイムライン合成ビュー）を開く
        let xRow = app.buttons["X投稿（3枚）"]
        XCTAssertTrue(xRow.waitForExistence(timeout: 15))
        xRow.tap()

        let exportButton = app.buttons["pageEditor.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15))
        sleep(2) // プレビュー画像の非同期ロードを待つ
        attachScreenshot(named: "06-x-timeline-composite")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
