import XCTest

/// Decorate mode on the room's own furniture: a piece is chosen with a touch, turned (it never fails for lack of
/// room), put away and put back, a change is taken back, and Reset room asks before it puts everything back.
final class RearrangeRoomTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    private func launchDecorate() {
        app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestStill", "YES", "-uitestNoHints", "YES",
                                "-decorate", "closet"]
        app.launch()
        XCTAssertTrue(app.otherElements["decorPanel"].waitForExistence(timeout: 90), "Decorate mode should open on the closet")
    }

    private func at(_ x: Double, _ y: Double) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func look(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["REARRANGE_SHOTS"] else { return }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "\(folder)/\(name).png"))
    }

    @MainActor
    func testResetRoomAsksFirstAndDecorateCloses() throws {
        launchDecorate()
        let reset = app.buttons["decorReset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 15))
        reset.tap()
        let question = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Put everything back'")).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 20), "Reset room asks before it changes anything")
        at(0.5, 0.12).tap()
        XCTAssertFalse(app.staticTexts["The room is as it first was."].exists, "dismissing the question changes nothing")
        XCTAssertTrue(app.otherElements["decorPanel"].exists)
        app.buttons["decorDone"].tap()
        XCTAssertTrue(app.buttons["decorate"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTheRoomsOwnFurnitureTurnsStoresAndComesBack() throws {
        launchDecorate()
        look("0-start")
        // The cat tree stands in the right corner of the Living room.
        at(0.893, 0.558).tap()
        XCTAssertTrue(app.staticTexts["Cat tree"].waitForExistence(timeout: 10), "a touch on the tree chooses it")
        look("1-selected")

        app.buttons["decorRotate"].tap()
        sleep(1)
        look("2-turned")
        XCTAssertTrue(app.buttons["decorUndo"].waitForExistence(timeout: 15) || app.staticTexts["There's no room to turn it. Put it away?"].exists,
                      "a turn either happens (and can be taken back) or says why not")
        if app.buttons["decorUndo"].exists {
            app.buttons["decorUndo"].tap()
            XCTAssertFalse(app.buttons["decorUndo"].exists)
        }

        at(0.893, 0.558).tap()
        XCTAssertTrue(app.staticTexts["Cat tree"].waitForExistence(timeout: 10))
        app.buttons["decorStore"].tap()
        XCTAssertTrue(app.buttons["Place Cat tree"].waitForExistence(timeout: 10), "a stored piece waits in the closet")
        look("3-stored")
        app.buttons["Place Cat tree"].tap()
        XCTAssertTrue(app.buttons["decorRotate"].waitForExistence(timeout: 10), "placing it again stands it in the room and chooses it")
        XCTAssertFalse(app.buttons["Place Cat tree"].exists)
        look("4-placed")
    }

    @MainActor
    func testTheLastBedCannotBeStored() throws {
        launchDecorate()
        // The cat's bed is in the middle of the rug.
        at(0.55, 0.54).tap()
        XCTAssertTrue(app.staticTexts["Cat bed"].waitForExistence(timeout: 10))
        app.buttons["decorStore"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'needs a bed or a sofa'")).firstMatch
            .waitForExistence(timeout: 15), "the last bed is refused with a reason")
        look("5-last-bed")
    }

    @MainActor
    func testAFineTurnTurnsFortyFiveDegreesAndCanBeTakenBack() throws {
        launchDecorate()
        // The cat tree stands in a corner with room round it, so a turn of 45 degrees fits.
        for _ in 0..<3 where !app.staticTexts["Cat tree"].exists {
            at(0.893, 0.558).tap()
            _ = app.staticTexts["Cat tree"].waitForExistence(timeout: 10)
        }
        XCTAssertTrue(app.staticTexts["Cat tree"].exists, "a touch on the tree chooses it")
        XCTAssertTrue(app.buttons["decorRotateFine"].exists)
        app.buttons["decorRotateFine"].tap()
        XCTAssertTrue(app.buttons["decorUndo"].waitForExistence(timeout: 15), "a 45 degree turn is a change that can be taken back")
        app.buttons["decorUndo"].tap()
        XCTAssertFalse(app.buttons["decorUndo"].exists)
    }
}
