import XCTest

/// Taps on the tab bar, anywhere on it, must never fall through to the room underneath.
final class TabBarTouchTests: XCTestCase {
    @MainActor
    func testTapsOnTheBarNeverReachTheRoom() throws {
        let app = XCUIApplication()
        // Skips onboarding, and has the room report the taps it gets as its accessibility value.
        app.launchArguments += ["-onboardingDone", "YES", "-uitestRoomTaps", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES"]
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
            ("between World and Moments", CGPoint(x: f.minX + f.width / 4, y: f.midY)),
            ("between Moments and Shop", CGPoint(x: f.minX + f.width / 2, y: f.midY)),
            ("between Shop and Us", CGPoint(x: f.minX + f.width * 3 / 4, y: f.midY)),
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

    /// A slow drag across all four tabs lands on the tab under the finger, and the avatars in the header offer the
    /// couple's profile.
    @MainActor
    func testDragAcrossTheBarAndOpenTheProfile() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES"]
        app.launch()

        let world = app.buttons["World"]
        let shop = app.buttons["Shop"]
        let us = app.buttons["Us"]
        XCTAssertTrue(world.waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 8)
        snapshot("world")

        world.press(forDuration: 0.3, thenDragTo: us, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(us.isSelected, "the drag across the bar should end on Us")
        snapshot("us")

        us.press(forDuration: 0.3, thenDragTo: shop, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(shop.isSelected, "the drag back should end on Shop")
        snapshot("shop")

        app.buttons["Moments"].tap()
        XCTAssertTrue(app.buttons["Moments"].isSelected)
        Thread.sleep(forTimeInterval: 2)
        snapshot("moments")

        app.buttons["Couple"].tap()
        XCTAssertTrue(app.buttons["Couple profile"].waitForExistence(timeout: 10), "the avatars should offer the profile")
        snapshot("couple-menu")
        app.buttons["Couple profile"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        snapshot("profile")
    }

    /// The tab's scroll view runs full-bleed under the header and the tab bar, which float over it, instead of
    /// stopping (and cutting its cards off) at the header's bottom edge.
    @MainActor
    func testScrollingRunsUnderTheHeaderAndTheTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["World"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 8)

        for tab in ["Shop", "Us"] {
            app.buttons[tab].tap()
            Thread.sleep(forTimeInterval: 1.5)
            let inbox = app.buttons["Inbox"].firstMatch
            let bar = app.otherElements["tabbar"].firstMatch
            XCTAssertTrue(inbox.waitForExistence(timeout: 10) && bar.exists, "the bars should show on \(tab)")
            // The tab's own scroll view is the tallest one; Shop also has a horizontal strip of chips.
            let scroll = app.scrollViews.allElementsBoundByIndex.max { $0.frame.height < $1.frame.height }
            let frame = try XCTUnwrap(scroll?.frame, "\(tab) should scroll")
            XCTAssertLessThan(frame.minY, inbox.frame.minY, "\(tab) should scroll under the header")
            XCTAssertGreaterThanOrEqual(frame.maxY, bar.frame.maxY - 1, "\(tab) should scroll under the tab bar")
        }
    }

    /// The header is the same on every tab: the Inbox top-left, the coins top-right with the couple's avatars in the
    /// corner to their right, each in the same place.
    @MainActor
    func testTheHeaderIsTheSameOnEveryTab() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["World"].waitForExistence(timeout: 60))
        Thread.sleep(forTimeInterval: 8)

        var first: [CGRect]?
        for tab in ["World", "Moments", "Shop", "Us"] {
            app.buttons[tab].tap()
            Thread.sleep(forTimeInterval: 1.5)
            let inbox = app.buttons["Inbox"].firstMatch
            let coins = app.otherElements["coins"].firstMatch
            let couple = app.buttons["Couple"].firstMatch
            XCTAssertTrue(inbox.waitForExistence(timeout: 10) && coins.exists && couple.exists, "the header should show on \(tab)")
            let frames = [inbox.frame, coins.frame, couple.frame].map(\.integral)
            XCTAssertLessThan(inbox.frame.maxX, coins.frame.minX, "the Inbox should be left of the coins on \(tab)")
            XCTAssertLessThanOrEqual(coins.frame.maxX, couple.frame.minX + 1, "the avatars should be right of the coins on \(tab)")
            // The "+" keeps the screen's right margin; on some CI Simulators `app.frame` is wider than the app's content.
            XCTAssertEqual(couple.frame.maxX, app.buttons["Add"].frame.maxX, accuracy: 12,
                           "the avatars should sit in the top-right corner on \(tab)")
            if let first {
                XCTAssertEqual(frames, first, "the header should not move between tabs (\(tab))")
            } else {
                first = frames
            }
            snapshot("header-\(tab.lowercased())")
        }
    }

    @MainActor
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
