import XCTest
import notify

/// The welcome screen plays its timeline without visible jank. That it fits the smallest iPhone and the largest text
/// is `OnboardingFitTests`.
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

    @MainActor
    func testTimelinePlaysWithoutHitchesAndFirstFrameIsQuick() throws {
        // A first launch on a fresh Simulator waits seconds on system services (a 3 s main-thread stall on CI), which
        // says nothing about the welcome; the measured launch is the second.
        let warm = launch()
        XCTAssertTrue(warm.buttons["Let's go"].waitForExistence(timeout: 60))
        warm.terminate()
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "NO", "-onboardingPage", "0", "-uitestNoRoom", "YES",
                                "-uitestNoHints", "YES", "-uitestWelcomeProbe", "-uitestWelcomeProbeHarness"]
        app.launch()
        // launch() is done waiting for the app to idle and snapshotting it: the welcome plays again from the start,
        // and the probe counts from here.
        notify_post("com.ourio.app.uitest.launched")
        // The script is under 3.5 s; let it play out and a little more. Nothing is queried meanwhile: each query
        // snapshots the app's accessibility tree on its main thread, which is itself a late frame.
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.buttons["Let's go"].waitForExistence(timeout: 20))
        // The probe shows its summary once the timeline has played.
        let probe = app.staticTexts["welcome.probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        let summary = probe.label
        print("welcome probe: \(summary)")
        XCTContext.runActivity(named: summary) { _ in }
        func value(_ key: String) -> Int {
            summary.split(separator: " ").compactMap { part -> Int? in
                let pair = part.split(separator: "=")
                return pair.count == 2 && pair[0] == key ? Int(pair[1]) : nil
            }.first ?? -1
        }
        XCTAssertTrue((0..<500).contains(value("firstFrameMs")), summary)
        // A GitHub runner's Simulator drops frames on its own (seen: 30 frames, one of them 133 ms), so there
        // the timeline only has to play; smoothness is held on a Mac.
        guard ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == nil else {
            XCTAssertGreaterThan(value("frames"), 0, summary)
            return
        }
        XCTAssertGreaterThan(value("frames"), 30, summary)
        XCTAssertEqual(value("janks"), 0, summary)
    }
}
