import XCTest

/// The cat sheet shows her four needs as gauges, met, in the middle and low, with a screenshot of each. Each state needs its
/// own launch, as `-uitestNeeds` is read at launch.
final class NeedBarsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testNeedBarsFull() throws { try shoot("full", needs: "1") }
    @MainActor func testNeedBarsMiddle() throws { try shoot("middle", needs: "0.5") }
    @MainActor func testNeedBarsLow() throws { try shoot("low", needs: "0.15") }

    @MainActor
    private func shoot(_ name: String, needs value: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES", "-uitestNeeds", value]
        app.launch()
        defer { app.terminate() }

        // A cold launch on CI can be slow; past a minute something is wrong. The splash leaves the tree only once
        // its fade ends; until then it takes the tap.
        let pet = app.buttons["pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 60), "the cat's button should show")
        let splash = app.descendants(matching: .any)["launch-splash"]
        XCTAssertTrue(splash.waitForNonExistence(timeout: 30), "the launch splash should lift")
        pet.tap()

        // The sheet is up once the line on its hero shows; then each need's tile.
        let sheet = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'With you two'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the cat's sheet should open")
        for need in ["Full", "Rested", "Playful", "Loved"] {
            XCTAssertTrue(app.descendants(matching: .any)[need].firstMatch.waitForExistence(timeout: 15),
                          "the \(need) tile should show")
        }
        // Every care is there, on a tile or under them, and the hero's line is on screen.
        for action in ["Feed", "Water", "Play", "Brush", "Pet"] {
            XCTAssertTrue(app.buttons[action].exists, "the \(action) care should show")
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Treat'")).firstMatch.exists)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertLessThanOrEqual(sheet.frame.maxY, app.frame.maxY, "the hero should be on screen")
        XCTAssertTrue(sheet.isHittable, "the hero should be reachable")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "needs-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
