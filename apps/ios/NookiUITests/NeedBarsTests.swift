import XCTest

/// The cat sheet shows her four need bars, full, in the middle and low, with a screenshot of each. Each state needs its
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

        // A cold launch on CI can be slow; past a minute something is wrong. Home is hidden from accessibility while
        // the launch splash covers it, so the button shows only once a tap can reach it.
        let pet = app.buttons["pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 60), "the cat's button should show")
        XCTAssertFalse(app.otherElements["launch-splash"].exists, "the splash should be gone before the tap")
        // The splash fades out over 0.8 s.
        Thread.sleep(forTimeInterval: 1)
        pet.tap()

        // The sheet is up once its last line shows; then each bar.
        let sheet = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'With you two'")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the cat's sheet should open")
        for need in ["Full", "Rested", "Playful", "Loved"] {
            XCTAssertTrue(app.descendants(matching: .any)[need].firstMatch.waitForExistence(timeout: 15),
                          "the \(need) bar should show")
        }
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "needs-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
