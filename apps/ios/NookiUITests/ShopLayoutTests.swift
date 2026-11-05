import XCTest

/// The Shop is one plain vertical scroll: no row of cards, chips or inks scrolls or snaps sideways inside it.
final class ShopLayoutTests: XCTestCase {
    @MainActor
    func testTheShopScrollsOnlyUpAndDown() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES",
                                "-uitestNoHints", "YES", "-tab", "shop"]
        app.launch()
        XCTAssertTrue(app.buttons["Shop"].waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)

        XCTAssertTrue(app.staticTexts["Daily deals"].waitForExistence(timeout: 10), "Today should show")
        for _ in 0..<3 {
            XCTAssertEqual(app.scrollViews.count, 1, "only the page itself should scroll")
            app.swipeUp()
        }
        XCTAssertEqual(app.scrollViews.count, 1, "only the page itself should scroll")
    }
}
