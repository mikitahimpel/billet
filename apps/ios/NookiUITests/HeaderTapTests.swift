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
        XCTAssertTrue(app.buttons["World"].waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)
        return app
    }

    @MainActor
    func testEveryTapOnTheRoomSwitchSwitches() throws {
        let app = launch()
        let room = app.buttons["Room"], city = app.buttons["City"]
        XCTAssertTrue(room.waitForExistence(timeout: 10) && city.exists, "an unpaired phone has both rooms")
        XCTAssertTrue(room.isSelected)

        // The pills are 34 pt to the eye; the spots near the top and bottom land outside them, in the hit area.
        XCTAssertGreaterThanOrEqual(room.frame.height, 44, "the switch should be 44 pt tall to the finger")
        for (tap, spot) in Self.spots.enumerated() {
            let target = tap.isMultiple(of: 2) ? city : room
            target.coordinate(withNormalizedOffset: spot).tap()
            XCTAssertTrue(target.isSelected, "tap \(tap + 1) on \(target.label) at \(spot) should switch to it")
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
