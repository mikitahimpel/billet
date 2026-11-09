import XCTest

/// The welcome screen fits the smallest iPhone and the largest text, and plays its timeline without a late frame.
final class WelcomeTests: XCTestCase {
    @MainActor
    private func launch(textSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "NO", "-onboardingPage", "0", "-uitestNoRoom", "YES",
                                "-uitestNoHints", "YES", "-uitestWelcomeProbe"]
        if let textSize { app.launchArguments += ["-UIPreferredContentSizeCategoryName", textSize] }
        app.launch()
        return app
    }

    /// Everything the screen says sits inside the window, so nothing is cut off at the edge or off-centre.
    @MainActor
    private func assertFits(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        let title = app.staticTexts["A cat for the two of you"]
        XCTAssertTrue(title.waitForExistence(timeout: 20), file: file, line: line)
        let go = app.buttons["Let's go"]
        XCTAssertTrue(go.waitForExistence(timeout: 20), file: file, line: line)
        for element in [title, go, app.buttons["I have an invite code"]] where element.exists {
            XCTAssertGreaterThanOrEqual(element.frame.minX, window.minX, "\(element.label)", file: file, line: line)
            XCTAssertLessThanOrEqual(element.frame.maxX, window.maxX, "\(element.label)", file: file, line: line)
        }
        XCTAssertEqual(title.frame.midX, window.midX, accuracy: 2, "the title is centred", file: file, line: line)
        XCTAssertLessThanOrEqual(go.frame.maxY, window.maxY, file: file, line: line)
    }

    @MainActor
    func testWelcomeFitsTheScreen() {
        assertFits(launch())
    }

    @MainActor
    func testWelcomeFitsAtTheLargestText() {
        assertFits(launch(textSize: "UICTContentSizeCategoryAccessibilityXXXL"))
    }

    @MainActor
    func testTimelinePlaysWithoutHitchesAndFirstFrameIsQuick() throws {
        let app = launch()
        // The script is under 3.5 s; let it play out and a little more. Nothing is queried meanwhile: each query
        // snapshots the app's accessibility tree on its main thread, which is itself a late frame.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.buttons["Let's go"].waitForExistence(timeout: 20))
        let summary = app.staticTexts["welcome.probe"].label
        print("welcome probe: \(summary)")
        XCTContext.runActivity(named: summary) { _ in }
        func value(_ key: String) -> Int {
            summary.split(separator: " ").compactMap { part -> Int? in
                let pair = part.split(separator: "=")
                return pair.count == 2 && pair[0] == key ? Int(pair[1]) : nil
            }.first ?? -1
        }
        XCTAssertGreaterThan(value("frames"), 30, summary)
        XCTAssertEqual(value("hitches"), 0, summary)
        XCTAssertTrue((0..<500).contains(value("firstFrameMs")), summary)
    }
}
