import XCTest

/// A horizontal drag across Home belongs to the room, never to the room switch.
final class RoomSwipeTests: XCTestCase {
    @MainActor
    func testHorizontalDragAcrossHomeLeavesTheRoomUnchanged() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] != nil, "needs a Simulator that can draw")
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoHints", "YES"]
        app.launch()

        let room = app.buttons["roomSwitch.Room"]
        let city = app.buttons["roomSwitch.City"]
        XCTAssertTrue(room.waitForExistence(timeout: 60))
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["launch-splash"])
        wait(for: [gone], timeout: 60)
        XCTAssertTrue(room.isSelected)

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5))
        for _ in 0..<2 {
            start.press(forDuration: 0.05, thenDragTo: end)
            end.press(forDuration: 0.05, thenDragTo: start)
        }
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(room.isSelected, "a horizontal drag changed the room")
        XCTAssertFalse(city.isSelected)
    }
}
