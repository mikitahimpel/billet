import XCTest

/// A sheet at full height covers the screen's width: the room shows at its sides only while it floats at a smaller detent.
/// The cat sheet at an accessibility text size outgrows the screen, so it is the one that asks for a height detent as tall as
/// the large one, which the system answers with an inset card.
final class SheetFullHeightTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor func testCatSheetFillsTheWidth() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES",
                                "-uitestNeeds", "0.5", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        defer { app.terminate() }

        let pet = app.buttons["pet"]
        XCTAssertTrue(pet.waitForExistence(timeout: 60), "the cat's button should show")
        XCTAssertTrue(app.descendants(matching: .any)["launch-splash"].waitForNonExistence(timeout: 30))
        pet.tap()
        let hero = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'With you two'")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 30), "the cat's sheet should open")
        Thread.sleep(forTimeInterval: 2)

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "cat-sheet-full-height"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The close button sits one gutter in from the sheet's trailing edge: at full width that is within 24 pt of
        // the screen's, while an inset card pushes it a further inset in.
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.exists, "the sheet's close button should show")
        XCTAssertGreaterThanOrEqual(close.frame.maxX, app.frame.maxX - 24,
                                    "the sheet should reach the screen's edge, not float with the room at its sides")
    }
}
