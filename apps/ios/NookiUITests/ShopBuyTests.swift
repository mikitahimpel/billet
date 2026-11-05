import XCTest

/// Selling is one tap: the hero offer's price pill buys it right there, with no sheet in between, and Undo shows.
final class ShopBuyTests: XCTestCase {
    @MainActor
    func testThePricePillBuysInOneTap() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES",
                                "-tab", "shop", "-shopCoins", "5000", "-shopOwned", "",
                                // A pair's room in memory, as buying needs one.
                                "-shopFixture", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Shop"].waitForExistence(timeout: 60))
        // The launch splash covers everything for up to 6 s.
        Thread.sleep(forTimeInterval: 8)

        // Matched by any type: the pill may also be a button.
        let coins = app.descendants(matching: .any)["coins"].firstMatch
        XCTAssertTrue(coins.waitForExistence(timeout: 10))
        // The pill formats the number for the device's locale, as "5,000" in English.
        let full = "\(5000.formatted()) coins"
        XCTAssertEqual(coins.label, full)

        let price = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Buy '")).firstMatch
        XCTAssertTrue(price.waitForExistence(timeout: 10), "Today should open on an offer with its price")
        price.tap()

        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5), "the buy should offer Undo")
        XCTAssertFalse(app.sheets.firstMatch.exists, "no sheet should come between the tap and the buy")
        XCTAssertNotEqual(coins.label, full, "the coins should go down at once")
    }
}
