import XCTest

/// A game that fills a need can be left: by its close button and by a swipe down from the top. One game each way
/// (the swipe's rule is `GameExitTests`). Run without the real room, which the UI tests cannot draw on CI; the touch
/// layer and the close button are the same.
final class GameCloseTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testWaterClosesByButton() throws { try leave("Water", swipe: false) }
    @MainActor func testFeedClosesBySwipe() throws { try leave("Feed", swipe: true) }

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
            // In the game's swipe band (its top 140 pt) but below the scene switch, which takes a drag that starts on
            // it, and below the status bar, whose drags pull down Notification Center and never reach the app.
            let segments = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gameScene'"))
            let switchBottom = segments.allElementsBoundByIndex.map(\.frame.maxY).max()
            let y = (switchBottom ?? app.frame.height * 0.1 - 12) + 12
            XCTAssertLessThan(y, 140, "the swipe band should reach below the scene switch")
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: y))
            from.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.midX, dy: y + 300)))
        } else {
            close.tap()
        }
        XCTAssertTrue(close.waitForNonExistence(timeout: 10), "the \(game) game should close")
        XCTAssertTrue(pet.waitForExistence(timeout: 10), "Home should be back")
    }
}
