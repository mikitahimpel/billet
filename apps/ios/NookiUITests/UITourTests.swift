import XCTest

/// Walks every screen it can reach and saves a screenshot of each, for the UI audit and before/after shots. A step
/// whose control is missing is skipped, so one moved button never loses the rest of the tour.
/// It runs only from the ios.yml shots job, which sets UISHOTS.
final class UITourTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UISHOTS"] == "1", "the tour runs only for shots")
    }

    @MainActor
    func testTourOfTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["World"].waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)
        shot("01-world")

        if tap(app.buttons["Add"]) {
            shot("02-add-menu")
            closeMenu(app)
        }
        if tap(app.buttons["pet"].firstMatch) {
            shot("03-pet-sheet")
            dismissSheet(app)
        }
        if tap(app.buttons["Moments"]) {
            shot("04-moments")
            if tap(app.buttons["All notes"]) {
                shot("05-moments-notes")
                dismissSheet(app)
            }
        }
        if tap(app.buttons["Shop"]) {
            shot("06-shop")
            app.swipeUp()
            shot("07-shop-scrolled")
        }
        if tap(app.buttons["Couple"]) {
            shot("08-profile")
            if tap(app.buttons["Settings"]) {
                shot("13-settings")
                app.swipeUp()
                shot("14-settings-scrolled")
                if tap(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Style'")).firstMatch) {
                    shot("15-style")
                    app.swipeUp()
                    shot("16-style-scrolled")
                }
            }
            dismissSheet(app)
        }
        if tap(app.buttons["Us"]) {
            shot("08-us")
            if tap(app.buttons["Mood"]) {
                shot("09-us-mood")
                closeMenu(app)
            }
            for (index, name) in ["Dates", "Wishlists", "Calendar"].enumerated() {
                let entry = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
                if tap(entry) {
                    shot("1\(index)-us-\(name.lowercased())")
                    // Each opens as a sheet over Us.
                    dismissSheet(app)
                }
            }
        }
        app.terminate()
    }

    @MainActor
    func testTourOfTheOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "NO", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES"]
        app.launch()
        Thread.sleep(forTimeInterval: 10)
        shot("20-onboarding")
        // The first steps move on with their one prominent button.
        for step in 1...5 {
            let next = app.buttons.matching(NSPredicate(format: "label IN {'Continue', 'Next', 'Get started', \"Let's go\", 'Skip', 'Not now'}")).firstMatch
            guard tap(next) else { break }
            shot("2\(step)-onboarding")
        }
        app.terminate()
    }

    /// Taps the element if it shows within a few seconds; true when it did.
    @MainActor
    private func tap(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5), element.isHittable else { return false }
        element.tap()
        Thread.sleep(forTimeInterval: 1.5)
        return true
    }

    /// Closes an open menu through the system's own dismiss region; a tap elsewhere could land on a control.
    @MainActor
    private func closeMenu(_ app: XCUIApplication) {
        let region = app.otherElements["PopoverDismissRegion"].firstMatch
        // Without the region, the screen's left margin, clear of the menus, cards and header; a tap on the
        // status bar doesn't close a menu.
        if region.exists { region.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.42)).tap() }
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 1.5)
    }

    @MainActor
    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
