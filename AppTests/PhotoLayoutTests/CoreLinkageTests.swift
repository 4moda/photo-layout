import XCTest
import PhotoLayoutCore
@testable import PhotoLayout

/// AppターゲットからCoreパッケージが利用できることを確認するスモークテスト。
final class CoreLinkageTests: XCTestCase {
    func testCorePackageIsLinked() {
        let ratio = AspectRatio(width: 16, height: 9)
        XCTAssertTrue(ratio.isLandscape)
        XCTAssertEqual(ratio.ratio, 16.0 / 9.0, accuracy: 1e-9)
    }
}
