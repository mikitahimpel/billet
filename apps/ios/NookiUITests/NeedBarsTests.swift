import XCTest

/// The cat sheet shows her four needs as bars; screenshots of it full, in the middle and low.
final class NeedBarsTests: XCTestCase {
    @MainActor func testNeedBarsFull() throws { try shoot("full", needs: "1") }
    @MainActor func testNeedBarsMiddle() throws { try shoot("middle", needs: "0.5") }
    @MainActor func testNeedBarsLow() throws { try shoot("low", needs: "0.15") }

    @MainActor
    private func shoot(_ name: String, needs value: String) throws {
        do {
            let app = XCUIApplication()
            app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNeeds", value]
            app.launch()

            let pet = app.buttons["pet"]
            XCTAssertTrue(pet.waitForExistence(timeout: 60))
            // The launch splash covers everything for up to 6 s.
            Thread.sleep(forTimeInterval: 8)
            pet.tap()

            for need in ["Full", "Rested", "Playful", "Loved"] {
                XCTAssertTrue(app.otherElements[need].firstMatch.waitForExistence(timeout: 10)
                    || app.staticTexts[need].firstMatch.exists, "the \(need) bar should show")
            }
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "needs-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
