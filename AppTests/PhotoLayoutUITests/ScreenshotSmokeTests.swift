import XCTest

/// 主要画面・主要状態・主要操作を巡回し、fastlane snapshot でスクリーンショットを撮る。
/// `fastlane snapshot` が本テストを駆動し、screenshots.html（一覧）を自動生成する。
///
/// スクショ名は `画面ID[-機能ID]-action-in-english` の安全なASCII名。
/// 画面ID・機能IDは docs/screens.md の一覧と対応し、フィルタ用インデックス
/// （tools/build_screenshot_index.py が生成する index.html）で画面別に絞り込める。
///
/// 状態を決定論的にするため常に `--reset-store`（インメモリ）で起動する。
/// デモ投入が要る画面は `--seed-demo` も付ける。
final class ScreenshotSmokeTests: XCTestCase {

    /// 決定論的な状態で起動するアプリ。`seed=false` なら何も無い空状態から始まる。
    @MainActor
    private func makeApp(seed: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-store"] + (seed ? ["--seed-demo"] : [])
        setupSnapshot(app)
        return app
    }

    // MARK: - S01 プロジェクト一覧: 空状態 → 新規作成 → S02 → S03

    @MainActor
    func testProjectListEmptyAndCreate() throws {
        let app = makeApp(seed: false)
        app.launch()

        XCTAssertTrue(app.navigationBars["PhotoLayout"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.otherElements["projectList.empty"].waitForExistence(timeout: 5)
                      || app.staticTexts["レイアウトがありません"].waitForExistence(timeout: 5))
        snapshot("S01-F02-project-list-empty-state")

        let addButton = app.buttons["projectList.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let squareButton = app.buttons["projectList.new_square"]
        XCTAssertTrue(squareButton.waitForExistence(timeout: 5))
        snapshot("S01-F03-project-list-paper-size-menu")
        squareButton.tap()

        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 10))
        snapshot("S02-empty-slide-editor")

        app.buttons["pageEditor.templateMenu"].tap()
        if app.buttons["田の字"].waitForExistence(timeout: 5) {
            sleep(1)
            snapshot("S02-F14-template-sheet")
            app.buttons["田の字"].tap()
            sleep(1)
            snapshot("S02-F14-four-grid-empty-slots")
        }

        if app.buttons["pageEditor.overview"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.overview"].tap()
            if app.buttons["overview.append"].waitForExistence(timeout: 5) {
                snapshot("S03-slide-overview")
                app.buttons["overview.append"].tap()
                sleep(1)
                snapshot("S03-F03-append-slide")
                app.buttons["overview.done"].tap()
            }
        }
    }

    // MARK: - S01 プロジェクト一覧: 複数プロジェクト（サムネイル・バッジ）・⋯削除メニュー

    @MainActor
    func testProjectListPopulated() throws {
        let app = makeApp(seed: true)
        app.launch()

        XCTAssertTrue(app.buttons["デモ"].waitForExistence(timeout: 15))
        sleep(1)
        snapshot("S01-F01-project-list-populated")

        // S01-F10: セル右上の⋯メニュー（削除）。開くだけで削除はしない。
        let cellMenu = app.buttons["projectList.menu"].firstMatch
        if cellMenu.waitForExistence(timeout: 3) {
            cellMenu.tap()
            if app.buttons["削除"].waitForExistence(timeout: 3) {
                snapshot("S01-F10-project-cell-delete-menu")
            }
        }
    }

    // MARK: - S01 用紙サイズ別の新規作成（S01-F04〜F08）→ 各アスペクトの空キャンバス

    @MainActor
    func testCanvasAspectsFromCreate() throws {
        let app = makeApp(seed: false)
        app.launch()
        XCTAssertTrue(app.navigationBars["PhotoLayout"].waitForExistence(timeout: 15))

        // 注: スクショ名はそのままファイル名になる。安全なASCII slugだけを使う。
        let sizes: [(id: String, name: String)] = [
            ("projectList.new_square", "S01-F04-create-square-canvas"),
            ("projectList.new_portrait45", "S01-F05-create-portrait-4-5-canvas"),
            ("projectList.new_portrait34", "S01-F06-create-portrait-3-4-canvas"),
            ("projectList.new_landscape169", "S01-F07-create-landscape-16-9-canvas"),
            ("projectList.new_landscape191", "S01-F08-create-landscape-1-91-1-canvas")
        ]
        for size in sizes {
            let add = app.buttons["projectList.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let choice = app.buttons[size.id]
            XCTAssertTrue(choice.waitForExistence(timeout: 5), "\(size.id) が無い")
            choice.tap()
            XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 10))
            sleep(1)
            snapshot(size.name)
            back(app)
        }
    }

    // MARK: - S02 デモ写真: 選択・枠比率・クロップ・枠・レイヤー / S04 書き出しプレビュー

    @MainActor
    func testDemoPhotoOperations() throws {
        let app = makeApp(seed: true)
        app.launch()

        let demoRow = app.buttons["デモ"]
        XCTAssertTrue(demoRow.waitForExistence(timeout: 15))
        demoRow.tap()
        XCTAssertTrue(app.buttons["pageEditor.export"].waitForExistence(timeout: 15))
        sleep(2)
        snapshot("S02-single-photo-natural-placement")

        if app.buttons["pageEditor.layerButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.layerButton"].tap()
            sleep(1)
            snapshot("S02-F15-layer-order-sheet")
            tapClose(app)
        }

        let export = app.buttons["pageEditor.export"]
        if export.isEnabled {
            export.tap()
            if app.buttons["preview.save"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("S04-export-preview")
            }
            tapClose(app)
        }

        let canvas = app.otherElements["pageEditor.canvas"].firstMatch
        guard canvas.exists else { return }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        guard app.buttons["pageEditor.deletePhoto"].waitForExistence(timeout: 5) else { return }
        snapshot("S02-F09-photo-selected-menu")

        if app.buttons["pageEditor.frameAspectMenu"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.frameAspectMenu"].tap()
            if app.buttons["4:5 縦"].waitForExistence(timeout: 3) {
                snapshot("S02-F09-frame-aspect-menu")
                app.buttons["4:5 縦"].tap()
                sleep(1)
            }
        }

        if app.buttons["pageEditor.cropButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.cropButton"].tap()
            if app.buttons["pageEditor.cropDone"].waitForExistence(timeout: 3) {
                sleep(1)
                snapshot("S02-F10-crop-mode")
                app.buttons["pageEditor.cropDone"].tap()
                sleep(1)
            }
        }

        if app.buttons["pageEditor.frameButton"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.frameButton"].tap()
            if app.buttons["白フチ"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("S02-F16-frame-preset-sheet")
            }
            tapClose(app)
        }
    }

    // MARK: - S02 レイアウト種別（コラージュ / 枠付き / パノラマ / X組写真）と S04 個別保存

    @MainActor
    func testLayoutKinds() throws {
        let app = makeApp(seed: true)
        app.launch()

        openDemo(app, "コラージュ（4枚）")
        snapshot("S02-collage-four-grid")
        back(app)

        openDemo(app, "枠付き（黒背景）")
        snapshot("S02-framed-black-background")
        back(app)

        openDemo(app, "パノラマ（3連）")
        snapshot("S02-panorama-three-slides")
        if app.buttons["pageEditor.overview"].waitForExistence(timeout: 3) {
            app.buttons["pageEditor.overview"].tap()
            if app.buttons["overview.done"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("S03-slide-overview-three-pages")
                captureOverviewMenus(app)
                app.buttons["overview.done"].tap()
            }
        }
        back(app)

        openDemo(app, "X投稿（3枚）")
        sleep(2)
        snapshot("S02-x-timeline-composite")
        // X投稿は1スライドに複数枚 → プレビューで「各写真を個別に保存」が出る
        if app.buttons["pageEditor.export"].isEnabled {
            app.buttons["pageEditor.export"].tap()
            if app.buttons["preview.save"].waitForExistence(timeout: 5) {
                sleep(1)
                snapshot("S04-F03-export-preview-save-each-photo")
            }
            tapClose(app)
        }
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

    /// S03 俯瞰のメニュー系（比率・背景・長押しカードメニュー）を撮る。
    /// メニューは popover。撮ったらナビバーをタップして閉じ、次を開く。
    @MainActor
    private func captureOverviewMenus(_ app: XCUIApplication) {
        let nav = app.navigationBars["スライド"]

        if app.buttons["overview.ratio"].waitForExistence(timeout: 3) {
            app.buttons["overview.ratio"].tap()
            if app.buttons["1:1"].waitForExistence(timeout: 3) {
                snapshot("S03-F11-carousel-ratio-menu")
            }
            if nav.exists { nav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }

        if app.buttons["overview.background"].waitForExistence(timeout: 3) {
            app.buttons["overview.background"].tap()
            if app.buttons["黒"].waitForExistence(timeout: 3) {
                snapshot("S03-F12-project-background-menu")
            }
            if nav.exists { nav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }

        // 長押しでSCRL風カードメニュー（左に追加/右に追加/複製/移動/削除 = S03-F04〜F09）
        // カードの要素型は環境で揺れるため型を問わず探す
        let card = app.descendants(matching: .any)["overview.row"].firstMatch
        if card.waitForExistence(timeout: 3) {
            card.press(forDuration: 1.1)
            if app.buttons["複製"].waitForExistence(timeout: 3) {
                snapshot("S03-F04-F09-card-context-menu")
            }
            if nav.exists { nav.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        }
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
