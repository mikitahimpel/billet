import XCTest

/// The Shop is one plain vertical scroll: only its category row and the daily deals row scroll sideways.
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
        let scrollers = "only the page, its category row and the deals row should scroll"
        for _ in 0..<3 {
            XCTAssertLessThanOrEqual(app.scrollViews.count, 3, scrollers)
            app.swipeUp()
        }
        XCTAssertLessThanOrEqual(app.scrollViews.count, 3, scrollers)
    }
}
