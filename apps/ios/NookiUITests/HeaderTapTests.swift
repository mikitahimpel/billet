import XCTest

/// Every tap on the World's controls does its thing, wherever on the control it lands and however quickly the taps
/// follow each other: the room switch, the Inbox and the avatars in the header. A tap that misses a control's hit area
/// falls through to the room underneath, so the taps land off-centre, where only the control's shape can catch them.
final class HeaderTapTests: XCTestCase {
    /// Off-centre spots inside a control's frame, as fractions of it, one per tap.
    private static let spots: [CGVector] = [
        CGVector(dx: 0.12, dy: 0.2), CGVector(dx: 0.88, dy: 0.8), CGVector(dx: 0.15, dy: 0.85),
        CGVector(dx: 0.85, dy: 0.15), CGVector(dx: 0.5, dy: 0.1), CGVector(dx: 0.5, dy: 0.9),
    ]

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // `-uitestNoRoom`: CI's virtual Macs can't draw RealityKit; the stand-in takes the taps the room would.
        app.launchArguments += [
            "-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES",
            "-uitestRoomTaps", "YES",
        ]
        app.launch()
        // Home is hidden from accessibility under the launch splash, so this also waits for the splash to go.
        XCTAssertTrue(app.buttons["World"].waitForExistence(timeout: 60))
        return app
    }

    @MainActor
    func testEveryTapOnTheRoomSwitchSwitches() throws {
        let app = launch()
        let name = app.buttons["roomSwitch"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "an unpaired phone has both rooms")
        XCTAssertEqual(name.value as? String, "Room")

        // The spots near the edges land outside the room's name, in the 44 pt hit area.
        XCTAssertGreaterThanOrEqual(name.frame.height, 44, "the switch should be 44 pt tall to the finger")
        for (tap, spot) in Self.spots.enumerated() {
            name.coordinate(withNormalizedOffset: spot).tap()
            let expected = tap.isMultiple(of: 2) ? "City" : "Room"
            XCTAssertEqual(name.value as? String, expected, "tap \(tap + 1) at \(spot) should switch to \(expected)")
        }
        XCTAssertEqual(app.otherElements["room"].value as? String, "0", "no tap on the switch should reach the room")
    }

    @MainActor
    func testEveryTapOnTheInboxOpensIt() throws {
        let app = launch()
        let inbox = app.buttons["Inbox"].firstMatch
        let sheet = app.navigationBars["Inbox"]
        XCTAssertGreaterThanOrEqual(inbox.frame.height, 44, "the Inbox should be 44 pt to the finger")
        for (tap, spot) in Self.spots.enumerated() {
            inbox.coordinate(withNormalizedOffset: spot).tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 3), "tap \(tap + 1) on the Inbox at \(spot) should open it")
            sheet.buttons["Done"].tap()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testEveryTapOnTheAvatarsOpensTheProfile() throws {
        let app = launch()
        let couple = app.buttons["Couple"].firstMatch
        let profile = app.navigationBars["Profile"]
        for (tap, spot) in Self.spots.enumerated() {
            couple.coordinate(withNormalizedOffset: spot).tap()
            XCTAssertTrue(
                profile.waitForExistence(timeout: 3), "tap \(tap + 1) on the avatars at \(spot) should open the profile")
            profile.buttons["Done"].tap()
            XCTAssertTrue(profile.waitForNonExistence(timeout: 5))
        }
    }
}
