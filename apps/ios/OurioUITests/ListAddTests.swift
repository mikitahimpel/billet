import XCTest

/// Every list kind adds from where it opens: a typed list from its own field and Add, Groceries also from a quick
/// pick, To watch, Places to go and the wishlist from a button in the list itself, not only from the toolbar.
/// Names are made unique per run, as the lists stay on the Simulator between runs.
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

    @MainActor
    func testAWatchListAddsFromTheList() throws {
        open("To watch")
        shot("watch-open")
        let add = app.buttons["Add a movie or show"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "an empty or filled watch list offers Add in the list")
        add.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let name = "Home movie \(run)"
        search.typeText(name)
        let asText = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add “'")).firstMatch
        XCTAssertTrue(asText.waitForExistence(timeout: 5), "a title search can't find is added as text")
        asText.tap()
        XCTAssertTrue(element(name).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add a movie or show"].exists, "the add tile stays in a filled list")
        shot("watch-filled")
    }

    @MainActor
    func testPlacesAddFromTheList() throws {
        open("Places to go")
        shot("places-open")
        let add = app.buttons["Add a country or place"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.typeText("Portugal")
        let country = app.buttons["Portugal"]
        XCTAssertTrue(country.waitForExistence(timeout: 5))
        country.tap()
        XCTAssertTrue(element("Portugal").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add a country or place"].exists)
        shot("places-filled")
    }

    @MainActor
    func testANewListStartsFromItsField() throws {
        scrollTo(app.buttons["New list"]).tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Packing \(run)")
        app.buttons.matching(NSPredicate(format: "label IN {'Confirm', 'Done'}")).firstMatch.tap()

        let field = app.textFields["Add an item"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start the list"].exists, "an empty list says how to start")
        shot("custom-empty")
        field.tap()
        field.typeText("Passport\n")
        XCTAssertTrue(element("Passport").waitForExistence(timeout: 5), "Return adds too")
        XCTAssertFalse(app.staticTexts["Start the list"].exists)
        shot("custom-filled")
    }

    @MainActor
    func testTheWishlistAddsFromTheList() throws {
        open("Wishlists")
        shot("wishlist-open")
        let add = app.buttons["Add a wish"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let title = app.textFields["What would you love?"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Linen scarf \(run)")
        app.buttons.matching(NSPredicate(format: "label IN {'Confirm', 'Done'}")).firstMatch.tap()
        XCTAssertTrue(element("Linen scarf \(run)").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add a wish"].exists, "a filled wishlist still offers Add")
        shot("wishlist-filled")
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
