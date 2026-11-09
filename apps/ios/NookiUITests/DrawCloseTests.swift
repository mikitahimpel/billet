import XCTest

/// The drawing composer opens over Home and closes again: its top bar once sat under the canvas, so Close did nothing.
final class DrawCloseTests: XCTestCase {
    @MainActor
    private func openDraw() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES"]
        app.launch()
        let coins = app.buttons["coins"]
        XCTAssertTrue(coins.waitForExistence(timeout: 60))
        let splash = app.otherElements["launch-splash"]
        wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)], timeout: 60)

        app.buttons["Add"].tap()
        // From iOS 27 a menu item's label carries its subtitle: "Draw, On M's lock screen".
        app.buttons.matching(NSPredicate(format: "label == 'Draw' OR label BEGINSWITH 'Draw, '")).firstMatch.tap()
        XCTAssertTrue(app.buttons["drawClose"].waitForExistence(timeout: 10), "the composer did not open")
        return app
    }

    @MainActor
    func testCloseReturnsToHome() {
        let app = openDraw()
        app.buttons["drawClose"].tap()
        XCTAssertTrue(app.buttons["coins"].waitForExistence(timeout: 10), "Home did not come back")
        XCTAssertFalse(app.buttons["drawClose"].exists)
    }

    @MainActor
    func testSwipingDownFromTheTopBarReturnsToHome() {
        let app = openDraw()
        let close = app.buttons["drawClose"]
        let start = close.coordinate(withNormalizedOffset: CGVector(dx: 6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 220)))
        XCTAssertTrue(app.buttons["coins"].waitForExistence(timeout: 10), "Home did not come back")
    }
}
