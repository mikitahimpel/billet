import XCTest

/// Screenshots of the cat sheet's four need bars, full, in the middle and low. Each state needs its own launch
/// (`-uitestNeeds` is read at launch), which is slow and flaky on CI's virtual Macs, so these run only in the ios.yml
/// shots job (`UISHOTS=1`), never in pull request CI.
final class NeedBarsTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UISHOTS"] == "1", "screenshots run only in the shots job")
        continueAfterFailure = false
    }

    @MainActor func testNeedBarsFull() throws { try shoot("full", needs: "1") }
    @MainActor func testNeedBarsMiddle() throws { try shoot("middle", needs: "0.5") }
    @MainActor func testNeedBarsLow() throws { try shoot("low", needs: "0.15") }

    @MainActor
    private func shoot(_ name: String, needs value: String) throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES", "-uitestNeeds", value]
        app.launch()
        defer { app.terminate() }

        // A cold launch on CI can be slow; past a minute something is wrong.
        let pet = app.buttons["pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 60), "the cat's button should show")
        // The launch splash covers everything for up to 6 s; wait until the button can take the tap.
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: pet)
        wait(for: [hittable], timeout: 30)
        Thread.sleep(forTimeInterval: 2)
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
