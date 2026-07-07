import XCTest

/// 主要画面を巡回してスクリーンショットをXCTAttachmentとして保存するスモークテスト。
/// CIがxcresultからPNGを抽出しartifact化する — Macを持たない開発者が
/// 「実際の画面」を確認する唯一の手段なので、画面を追加したらここにも撮影を追加すること。
final class ScreenshotSmokeTests: XCTestCase {
    @MainActor
    func testProjectListCreateFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 一覧（空 or 既存行）が表示されるまで待つ
        let navTitle = app.navigationBars["PhotoLayout"]
        XCTAssertTrue(navTitle.waitForExistence(timeout: 15))
        attachScreenshot(named: "01-project-list")

        // ＋で下書き作成 → 行が現れる
        app.buttons["projectList.add"].tap()
        let row = app.staticTexts["無題のレイアウト"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        attachScreenshot(named: "02-project-created")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
