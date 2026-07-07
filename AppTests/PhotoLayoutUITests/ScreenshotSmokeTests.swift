import XCTest

/// 主要画面を巡回してスクリーンショットをXCTAttachmentとして保存するスモークテスト。
/// CIがxcresultからPNGを抽出しartifact化する — Macを持たない開発者が
/// 「実際の画面」を確認する唯一の手段なので、画面を追加したらここにも撮影を追加すること。
final class ScreenshotSmokeTests: XCTestCase {
    @MainActor
    func testCaptureRootScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["root.title"].waitForExistence(timeout: 15))
        attachScreenshot(named: "01-root")
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
