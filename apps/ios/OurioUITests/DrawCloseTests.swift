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
        // One snapshot of the button, then plain screen coordinates: a drag measured from the element looks it up again
        // for the start, the end and every retry, and each lookup walks the whole composer's accessibility tree.
        let bar = app.buttons["drawClose"].frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: bar.maxX + 160, dy: bar.midY))
        start.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: bar.maxX + 160, dy: bar.midY + 220)))
        XCTAssertTrue(app.buttons["coins"].waitForExistence(timeout: 10), "Home did not come back")
    }
}
