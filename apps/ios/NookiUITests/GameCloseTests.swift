import XCTest

/// Each game that fills a need can be left: by its close button and by a swipe down from the top. Run without the real
/// room, which the UI tests cannot draw on CI; the touch layer and the close button are the same.
final class GameCloseTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testFeedClosesByButton() throws { try leave("Feed", swipe: false) }
    @MainActor func testWaterClosesByButton() throws { try leave("Water", swipe: false) }
    @MainActor func testBrushClosesByButton() throws { try leave("Brush", swipe: false) }
    @MainActor func testFeedClosesBySwipe() throws { try leave("Feed", swipe: true) }
    @MainActor func testWaterClosesBySwipe() throws { try leave("Water", swipe: true) }
    @MainActor func testBrushClosesBySwipe() throws { try leave("Brush", swipe: true) }

    @MainActor
    private func leave(_ game: String, swipe: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES"]
        app.launch()
        defer { app.terminate() }

        let pet = app.buttons["pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 60), "Home should show")
        XCTAssertTrue(app.descendants(matching: .any)["launch-splash"].waitForNonExistence(timeout: 30))
        pet.tap()
        let tile = app.buttons[game]
        XCTAssertTrue(tile.waitForExistence(timeout: 30), "the \(game) tile should show")
        tile.tap()

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 30), "the \(game) game should open")
        if swipe {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
        } else {
            close.tap()
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "the \(game) game should close")
        XCTAssertTrue(pet.waitForExistence(timeout: 10), "Home should be back")
    }
}
