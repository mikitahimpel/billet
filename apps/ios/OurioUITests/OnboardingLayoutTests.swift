import XCTest

/// The onboarding pages share one bottom: the primary action sits at the same height on every page, whatever the page
/// above it holds, and the welcome's terms can be read clear of the actions, on the smallest phone and at the largest
/// text.
final class OnboardingLayoutTests: XCTestCase {
    @MainActor
    private func launch(page: Int? = nil, open: String? = nil, textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "NO", "-onboardingPage", "\(page ?? 0)", "-uitestNoRoom", "YES",
                                "-uitestNoHints", "YES"]
        if let open { app.launchArguments += ["-onboardingOpen", open] }
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        return app
    }

    @MainActor
    private func primaryFrame(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> CGRect {
        let primary = app.buttons["onboarding.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 20), file: file, line: line)
        return primary.frame
    }

    @MainActor
    func testThePrimaryActionSitsAtTheSameHeightOnEveryPage() {
        var frames: [String: CGRect] = [:]
        for page in 0...3 {
            let app = launch(page: page)
            frames["page \(page)"] = primaryFrame(app)
            app.terminate()
        }
        let app = launch(page: 1, open: "catCoat")
        frames["coat"] = primaryFrame(app)
        let window = app.windows.firstMatch.frame
        let welcome = frames["page 0"]!
        XCTAssertLessThanOrEqual(welcome.maxY, window.maxY)
        // Nothing reserved under it: the gap to the window's edge is the safe area and one spacing token.
        XCTAssertLessThan(window.maxY - welcome.maxY, 60, "the primary sits on the bottom")
        for (name, frame) in frames {
            XCTAssertEqual(frame.maxY, welcome.maxY, accuracy: 1, "\(name)'s primary is where the welcome's is")
        }
    }

    @MainActor
    private func assertTermsClearTheActions(_ app: XCUIApplication, file: StaticString = #filePath,
                                            line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let go = primaryFrame(app, file: file, line: line)
        let terms = app.staticTexts["welcome.terms"]
        XCTAssertTrue(terms.waitForExistence(timeout: 20), file: file, line: line)
        // At the largest text the welcome scrolls; the terms are read where they come into view.
        for _ in 0..<6 where !terms.isHittable || terms.frame.maxY > go.minY {
            app.swipeUp()
        }
        XCTAssertTrue(terms.isHittable, "the terms can be reached", file: file, line: line)
        XCTAssertGreaterThanOrEqual(terms.frame.minY, window.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(terms.frame.maxY, go.minY, "the terms sit above the button", file: file, line: line)
        let invite = app.buttons["I have an invite code"]
        if invite.exists {
            XCTAssertLessThanOrEqual(terms.frame.maxY, invite.frame.minY, file: file, line: line)
            XCTAssertLessThanOrEqual(invite.frame.maxY, go.minY, file: file, line: line)
        }
    }

    @MainActor
    func testTheWelcomeTermsClearTheActions() {
        assertTermsClearTheActions(launch())
    }

    @MainActor
    func testTheWelcomeTermsClearTheActionsAtTheLargestText() {
        assertTermsClearTheActions(launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL"))
    }
}
