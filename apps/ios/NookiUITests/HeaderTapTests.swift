import XCTest

/// Every header button opens what it names, with the real room under it: the room draws with RealityKit and takes its
/// own touches, which the other header tests leave out with `-uitestNoRoom`.
final class HeaderTapTests: XCTestCase {
    @MainActor
    func testEveryHeaderButtonOpensItsSheetOverTheRealRoom() throws {
        // RealityKit cannot draw on CI's virtual Macs.
        try XCTSkipIf(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "needs a Simulator that can draw")
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoHints", "YES"]
        app.launch()

        let splash = app.otherElements["launch-splash"]
        let coins = app.buttons["coins"]
        XCTAssertTrue(coins.waitForExistence(timeout: 60))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: splash)
        wait(for: [gone], timeout: 60)

        // What each sheet shows that nothing else on screen does.
        func text(_ format: String) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        }
        let sheets: [(button: String, shows: XCUIElement, name: String)] = [
            ("Couple", app.navigationBars["Profile"], "the profile"),
            ("coins", text("label CONTAINS 'coins for the two of you'"), "the Coins sheet"),
            ("mood", text("label BEGINSWITH 'How are you,'"), "the mood picker"),
            ("Inbox", text("label == 'Inbox' AND NOT (elementType == 9) OR label CONTAINS 'Once you'"), "the Inbox"),
        ]
        var report: [String] = []
        for sheet in sheets {
            let button = app.buttons[sheet.button]
            var taps = 0
            while taps < 3, !sheet.shows.exists {
                button.tap()
                taps += 1
                _ = sheet.shows.waitForExistence(timeout: 3)
            }
            report.append("\(sheet.button): \(sheet.shows.exists ? "opened after \(taps) tap(s)" : "never opened")")
            app.swipeDown(velocity: .fast)
            Thread.sleep(forTimeInterval: 1.5)
            if sheet.shows.exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3)).tap() }
            XCTAssertTrue(button.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(report.filter { !$0.contains("after 1 tap") }, [], report.joined(separator: "; "))
    }
}
