import XCTest

/// Decorate mode: the closet shows, Reset room asks before it puts everything back, and Done leaves the mode.
final class RearrangeRoomTests: XCTestCase {
    @MainActor
    func testResetRoomAsksFirstAndDecorateCloses() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES",
                                "-decorate", "closet"]
        app.launch()
        let panel = app.otherElements["decorPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 90), "Decorate mode should open on the closet")

        let reset = app.buttons["decorReset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Reset room asks before it changes anything")
        cancel.tap()
        XCTAssertTrue(panel.exists)

        app.buttons["decorDone"].tap()
        XCTAssertTrue(app.buttons["decorate"].waitForExistence(timeout: 10))
    }
}
