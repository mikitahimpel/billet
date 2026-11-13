import XCTest

/// A list adds from its own field and Add, Groceries also from a quick pick. What each kind of list holds after an add
/// is `ListAddingTests`. Names are made unique per run, as the lists stay on the Simulator between runs.
final class ListAddTests: XCTestCase {
    private var app: XCUIApplication!
    private let run = String(Int(Date().timeIntervalSince1970) % 100_000)

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestStill", "YES",
                                "-uitestNoHints", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Us"].waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)
        app.buttons["Us"].tap()
    }

    @MainActor
    func testGroceriesAddFromTheFieldAndAQuickPick() throws {
        open("Groceries")
        shot("groceries-open")
        let field = app.textFields["Add something to buy"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the add field shows without typing first")
        let idleAdd = app.buttons.matching(NSPredicate(format: "label == 'Add' AND isEnabled == false")).firstMatch
        XCTAssertTrue(idleAdd.exists, "Add waits for a name")

        let name = "Oat milk \(run)"
        field.tap()
        field.typeText(name)
        app.buttons["Add \(name)"].tap()
        XCTAssertTrue(element(name).waitForExistence(timeout: 5), "the typed item is on the list")
        XCTAssertEqual(field.value as? String, "Add something to buy", "the field is empty for the next one")

        // A quick pick adds in one tap while the field is up.
        let pick = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label != 'Add'")).firstMatch
        if pick.waitForExistence(timeout: 3) {
            let picked = String(pick.label.dropFirst("Add ".count))
            pick.tap()
            XCTAssertTrue(element(picked).waitForExistence(timeout: 5), "the quick pick is on the list")
        }
        app.swipeDown()
        shot("groceries-filled")
    }

    // MARK: Helpers

    @MainActor
    private func open(_ card: String) {
        let entry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", card)).firstMatch
        scrollTo(entry).tap()
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element) should be on screen")
        return element
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    /// Kept with the result, and written to `LISTSHOTS` when set, to look at by eye.
    @MainActor
    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.6)
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["LISTSHOTS"] {
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
