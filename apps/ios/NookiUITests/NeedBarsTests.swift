import XCTest

/// The cat sheet shows her four needs as bars; screenshots of it full, in the middle and low.
final class NeedBarsTests: XCTestCase {
    @MainActor
    func testNeedBarsFullMiddleLow() throws {
        for (name, value) in [("full", "1"), ("middle", "0.5"), ("low", "0.15")] {
            let app = XCUIApplication()
            app.launchArguments += ["-onboardingDone", "YES", "-uitestNeeds", value]
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
