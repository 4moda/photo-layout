import XCTest

/// 主要画面・主要操作を巡回して fastlane snapshot でスクリーンショットを撮る。
/// `fastlane snapshot` が本テストを駆動し、screenshots.html（一覧）を自動生成する。
///
/// スクショ名は `シナリオ｜操作｜結果` の構造化名。どのシナリオのどの操作の結果かを名前で紐づける。
final class ScreenshotSmokeTests: XCTestCase {

    // MARK: - プロジェクト一覧・新規作成・テンプレート

    @MainActor
    func testProjectListCreateAndTemplate() throws {
        let app = XCUIApplication()
        setupSnapshot(app)
        app.launch()

        XCTAssertTrue(app.navigationBars["PhotoLayout"].waitForExistence(timeout: 15))
        snapshot("プロジェクト一覧｜起動｜レイアウト一覧")

        let addButton = app.buttons["projectList.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let squareButton = app.buttons["projectList.new_square"]
        XCTAssertTrue(squareButton.waitForExistence(timeout: 5))
        snapshot("プロジェクト一覧｜＋メニューを開く｜用紙サイズ選択メニュー")
        squareButton.tap()

        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 10))
        snapshot("新規スライド｜作成直後｜スライド編集（空・中央＋）")

        app.buttons["pageEditor.templateMenu"].tap()
        if app.buttons["田の字"].waitForExistence(timeout: 5) {
            sleep(1)
            snapshot("新規スライド｜テンプレボタンを押す｜型枠ビジュアル一覧シート")
            app.buttons["田の字"].tap()
            sleep(1)
            snapshot("新規スライド｜田の字を選ぶ｜空スロット4つ（グレー範囲）")
        }

        if app.buttons["pageEditor.overview"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.overview"].tap()
            if app.buttons["overview.append"].waitForExistence(timeout: 5) {
                snapshot("新規スライド｜スライドボタンを押す｜スライド一覧（俯瞰）")
                app.buttons["overview.append"].tap()
                sleep(1)
                snapshot("スライド一覧｜スライドを追加｜2スライドに増える")
                app.buttons["overview.done"].tap()
            }
        }
    }

    // MARK: - デモ写真: 選択・クロップ・枠・レイヤー・書き出しプレビュー

    @MainActor
    func testDemoPhotoOperations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        setupSnapshot(app)
        app.launch()

        let demoRow = app.buttons["デモ"]
        XCTAssertTrue(demoRow.waitForExistence(timeout: 15))
        demoRow.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)
        snapshot("デモ写真｜開く｜自然配置（元アスペクトのまま中央）")

        if app.buttons["pageEditor.layerButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.layerButton"].tap()
            sleep(1)
            snapshot("デモ写真｜レイヤーボタンを押す｜重なり順リスト")
            tapClose(app)
        }

        let export = app.buttons["pageEditor.export"]
        if export.isEnabled {
            export.tap()
            if app.buttons["preview.save"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("デモ写真｜ダウンロードを押す｜書き出しプレビュー画面")
            }
            tapClose(app)
        }

        let canvas = app.otherElements["pageEditor.canvas"].firstMatch
        guard canvas.exists else { return }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard app.buttons["pageEditor.deletePhoto"].waitForExistence(timeout: 5) else { return }
        snapshot("デモ写真｜写真をタップ｜写真メニュー＋四隅ハンドル")

        if app.buttons["pageEditor.cropButton"].exists {
            app.buttons["pageEditor.cropButton"].tap()
            if app.buttons["pageEditor.cropDone"].waitForExistence(timeout: 3) {
                sleep(1)
                snapshot("デモ写真｜クロップを押す｜クロップ調整モード")
                app.buttons["pageEditor.cropDone"].tap()
                sleep(1)
            }
        }

        if app.buttons["pageEditor.frameButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.frameButton"].tap()
            if app.buttons["白フチ"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("デモ写真｜枠ボタンを押す｜枠プリセット一覧シート")
            }
            tapClose(app)
        }
    }

    // MARK: - レイアウト種別（コラージュ / 枠付き / パノラマ / X組写真）

    @MainActor
    func testLayoutKinds() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--seed-demo"]
        setupSnapshot(app)
        app.launch()

        openDemo(app, "コラージュ（4枚）")
        snapshot("コラージュ｜開く｜田の字4枚の合成")
        back(app)

        openDemo(app, "枠付き（黒背景）")
        snapshot("枠付き｜開く｜黒背景＋白フチ＋マット")
        back(app)

        openDemo(app, "パノラマ（3連）")
        snapshot("パノラマ｜開く｜1枚が3スライドに跨る")
        if app.buttons["pageEditor.overview"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.overview"].tap()
            if app.buttons["overview.done"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("パノラマ｜スライドボタンを押す｜スライド一覧（3スライド）")
                app.buttons["overview.done"].tap()
            }
        }
        back(app)

        openDemo(app, "X投稿（3枚）")
        sleep(2)
        snapshot("X組写真｜開く｜タイムライン合成（左大＋右2）")
    }

    // MARK: - helpers

    @MainActor
    private func openDemo(_ app: XCUIApplication, _ title: String) {
        let row = app.buttons[title]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "\(title) が一覧に無い")
        row.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["PhotoLayout"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func tapClose(_ app: XCUIApplication) {
        let close = app.buttons["閉じる"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        sleep(1)
    }
}
