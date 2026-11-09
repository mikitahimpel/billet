import XCTest

/// Screenshots every Shop sheet variant: items of each rarity, one for Mochi, one owned, one the couple can't afford,
/// and the featured and bundle sets. Each launches straight into its sheet through the Shop's DEBUG launch arguments.
/// It runs only from the ios.yml shots job, which sets UISHOTS.
final class ShopSheetShots: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UISHOTS"] == "1", "shots run only in the shots job")
    }

    private static let variants: [(name: String, arguments: [String])] = [
        ("01-item-common", ["-shopItem", "monstera"]),
        ("02-item-epic", ["-shopItem", "armchair"]),
        ("03-item-legendary", ["-shopItem", "lantern"]),
        ("04-item-for-mochi", ["-shopItem", "yarn"]),
        ("05-item-owned", ["-shopItem", "lamp", "-shopOwned", "lamp,rug"]),
        ("06-item-not-enough", ["-shopItem", "tower", "-shopCoins", "20"]),
        ("07-set-featured", ["-shopSet", "featured"]),
        ("08-set-bundle", ["-shopSet", "mochi-playday", "-shopSection", "bundles"]),
        ("09-set-owned", ["-shopSet", "mochi-playday", "-shopSection", "bundles", "-shopOwned", "yarn,mouse,tower"]),
    ]

    @MainActor
    func testShopSheets() throws {
        for (index, variant) in Self.variants.enumerated() {
            let app = XCUIApplication()
            app.launchArguments += ["-onboardingDone", "YES", "-uitestNoRoom", "YES", "-uitestNoHints", "YES",
                                    "-tab", "shop"]
            app.launchArguments += variant.arguments
            // The same balance and closet for every shot, unless the variant sets its own; each key is passed once.
            if !variant.arguments.contains("-shopCoins") { app.launchArguments += ["-shopCoins", "560"] }
            if !variant.arguments.contains("-shopOwned") { app.launchArguments += ["-shopOwned", "lamp,rug"] }
            app.launch()
            _ = app.buttons["Shop"].waitForExistence(timeout: 60)
            // The launch splash covers everything for up to 6 s, longer on the first, cold launch; then the sheet
            // slides up.
            Thread.sleep(forTimeInterval: index == 0 ? 16 : 9)
            shot(variant.name)
            // The large detent, where the sheet has one.
            app.swipeUp()
            Thread.sleep(forTimeInterval: 1.5)
            shot(variant.name + "-up")
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
