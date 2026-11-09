import XCTest

/// Screenshots every reachable screen for the UI audit; a step whose control is missing is skipped, so one moved
/// button never loses the rest. Runs only from the ios.yml shots job, which sets UISHOTS.
final class UITourTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UISHOTS"] == "1", "the tour runs only for shots")
    }

    @MainActor
    func testTourOfTheApp() throws {
        let app = XCUIApplication()
        // Needs half full, so the cat's sheet shows its bars rather than "settling in".
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES",
                                "-uitestNeeds", "0.5"]
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
        // The Coins sheet and the profile come before the Shop, whose scroll can open an item sheet on the way.
        if tap(app.buttons["coins"]) {
            shot("18-coins")
            app.swipeUp()
            shot("19-coins-scrolled")
            dismissSheet(app)
        }
        if tap(app.buttons["Couple"]) {
            shot("08-profile")
            if tap(app.buttons["Edit profile"]) {
                shot("17-profile-edit")
                _ = tap(app.navigationBars.buttons.element(boundBy: 0))
            }
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
            closeProfile(app)
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
            // In case the swipe landed on a card and opened its sheet.
            dismissSheet(app)
        }
        if tap(app.buttons["Us"]) {
            shot("08-us")
            if tap(app.buttons["mood"]) {
                shot("09-mood")
                dismissSheet(app)
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

    /// Backs out of whatever the profile pushed, then closes it with Close; a swipe on a pushed screen can scroll it
    /// instead of closing the sheet.
    @MainActor
    private func closeProfile(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let done = app.buttons["Close"]
            if done.exists, done.isHittable {
                done.tap()
                Thread.sleep(forTimeInterval: 1.5)
                return
            }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { break }
            back.tap()
            Thread.sleep(forTimeInterval: 1)
        }
        dismissSheet(app)
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 1.5)
        // On a tall screen the swipe can scroll the sheet instead of closing it; a tap in the left margin above a
        // part-height sheet closes it, and lands on nothing once it's gone.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
