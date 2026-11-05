import XCTest

/// Screenshots the onboarding coat step in each of the six coats, then a tap from one coat to the next.
/// It runs only from the ios.yml shots job, which sets UISHOTS.
final class CoatPickerShots: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UISHOTS"] == "1", "shots run only in the shots job")
    }

    private static let coats = ["grey", "ginger", "cream", "tuxedo", "black", "calico"]

    @MainActor
    func testCoatStep() throws {
        for (index, coat) in Self.coats.enumerated() {
            let app = XCUIApplication()
            app.launchArguments += ["-onboardingDone", "NO", "-onboardingOpen", "catCoat", "-catCoat", coat,
                                    "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES"]
            app.launch()
            _ = app.staticTexts["Choose your cat"].waitForExistence(timeout: 60)
            // The launch splash covers everything for a few seconds, longer on the first, cold launch.
            Thread.sleep(forTimeInterval: index == 0 ? 14 : 8)
            shot("0\(index + 1)-coat-\(coat)")
            app.terminate()
        }
    }

    @MainActor
    private func shot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
