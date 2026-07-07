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

        app.buttons["projectList.add"].tap()
        let row = app.staticTexts["無題のレイアウト"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attachScreenshot(named: "02-project-created")
    }

    @MainActor
    func testPageEditorWithDemoPhoto() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        app.launch()

        // デモプロジェクト（生成写真1枚・白余白プリセット入り）を開く
        let demoRow = app.staticTexts["デモ"]
        XCTAssertTrue(demoRow.waitForExistence(timeout: 15))
        demoRow.tap()

        // エディタ到達の確認はツールバーの書き出しボタンで行う（Canvasは要素階層に出ないことがある）
        let exportButton = app.buttons["pageEditor.export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15))
        sleep(2) // プレビュー画像の非同期ロードを待つ
        attachScreenshot(named: "03-editor-white-margin")

        // 枠プリセットを黒背景＋白フチへ切替 → プレビューが変わることをスクショで示す
        app.buttons["pageEditor.presetMenu"].tap()
        let preset = app.buttons["黒背景＋白フチ"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        // 反映を待つ（プレビュー画像の再生成）
        sleep(2)
        attachScreenshot(named: "04-editor-black-background")

        // マット配置（写真全体＋余白）へ切替
        app.buttons["pageEditor.matButton"].tap()
        sleep(2)
        attachScreenshot(named: "05-editor-matted")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
