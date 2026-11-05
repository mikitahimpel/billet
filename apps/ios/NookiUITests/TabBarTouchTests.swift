import XCTest

/// Taps on the tab bar, anywhere on it, must never fall through to the room underneath.
final class TabBarTouchTests: XCTestCase {
    @MainActor
    func testTapsOnTheBarNeverReachTheRoom() throws {
        let app = XCUIApplication()
        // Skips onboarding, and has the room report the taps it gets as its accessibility value.
        app.launchArguments += ["-onboardingDone", "YES", "-uitestRoomTaps", "YES"]
        app.launch()

        let bar = app.otherElements["tabbar"]
        let room = app.otherElements["room"]
        let add = app.buttons["Add"]
        let world = app.buttons["World"]
        XCTAssertTrue(bar.waitForExistence(timeout: 60))
        XCTAssertTrue(room.waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)

        // The counter works: a tap in the middle of the room reaches it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertEqual(room.value as? String, "1", "a tap on the room should reach it")

        let f = bar.frame
        let gapX = (f.maxX + add.frame.minX) / 2
        let points: [(String, CGPoint)] = [
            ("leading edge", CGPoint(x: f.minX + 3, y: f.midY)),
            ("trailing edge", CGPoint(x: f.maxX - 3, y: f.midY)),
            ("top edge", CGPoint(x: f.minX + f.width / 6, y: f.minY + 2)),
            ("bottom edge", CGPoint(x: f.minX + f.width / 6, y: f.maxY - 2)),
            ("between World and Moments", CGPoint(x: f.minX + f.width / 3, y: f.midY)),
            ("between Moments and Shop", CGPoint(x: f.minX + f.width * 2 / 3, y: f.midY)),
            ("gap before +", CGPoint(x: gapX, y: f.midY)),
        ]
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for (name, point) in points {
            origin.withOffset(CGVector(dx: point.x, dy: point.y)).tap()
            // Back to World, so the room is live under the bar for the next tap.
            world.tap()
            XCTAssertEqual(room.value as? String, "1", "the tap on the bar's \(name) reached the room")
        }
    }

    /// A slow drag along the bar lands on the tab under the finger, and the avatars in the header open Us.
    @MainActor
    func testDragAcrossTheBarAndOpenUs() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES"]
        app.launch()

        let world = app.buttons["World"]
        let shop = app.buttons["Shop"]
        XCTAssertTrue(world.waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 8)
        snapshot("world")

        world.press(forDuration: 0.3, thenDragTo: shop, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(shop.isSelected, "the drag should end on Shop")
        snapshot("shop")

        app.buttons["Moments"].tap()
        Thread.sleep(forTimeInterval: 2)
        snapshot("moments")

        app.buttons["Us"].tap()
        XCTAssertTrue(app.staticTexts["Us"].waitForExistence(timeout: 10), "the avatars should open Us")
        Thread.sleep(forTimeInterval: 1)
        snapshot("us")
    }

    @MainActor
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
