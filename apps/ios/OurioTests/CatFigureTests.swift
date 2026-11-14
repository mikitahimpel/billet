import Foundation
import RoomInterface
import Testing
import UIKit
@testable import Billet

struct CatFigureTests {
    @Test(arguments: [
        ("MochiPortrait", "grey"), ("MochiPortrait-ginger", "ginger"), ("MochiPortrait-calico", "calico"),
        ("MochiPortrait-", "grey"), ("Other", "grey"),
    ])
    func anAvatarNamesHerCoat(avatar: String, coat: String) {
        #expect(HeroFigure.coat(forAvatar: avatar) == coat)
        #expect(HeroFigure.name(forAvatar: avatar) == "Hero-\(coat)")
    }

    @Test(arguments: RoomInterface.CatCoat.allCases)
    func everyCoatHasAHeroDownsampledTo3by4(coat: RoomInterface.CatCoat) throws {
        let image = try #require(HeroFigure.image(for: coat.avatar))
        let longer = max(image.size.width, image.size.height)
        #expect(longer <= CGFloat(HeroFigure.maxPixels))
        #expect(longer >= CGFloat(HeroFigure.maxPixels) - 1)
        #expect(abs(image.size.width / image.size.height - 0.75) < 0.01)
    }

    @Test func anUnknownCoatFallsBackToTheGreyTabby() throws {
        let unknown = try #require(HeroFigure.image(for: "MochiPortrait-tiger"))
        let grey = try #require(HeroFigure.image(for: "MochiPortrait"))
        #expect(unknown === grey)
    }

    /// The extension bundles her hero in every coat (project.yml), so a widget never falls back to the symbol, and
    /// none of the app's blink or ear patches.
    @Test(arguments: RoomInterface.CatCoat.allCases)
    func theWidgetExtensionBundlesEveryCoat(coat: RoomInterface.CatCoat) throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let widgets = try #require(Bundle(url: plugins.appending(path: "OurioWidgets.appex")))
        #expect(widgets.url(forResource: "Hero-\(coat.rawValue)", withExtension: "webp") != nil)
        #expect(HeroFigure.image(for: coat.avatar, in: widgets) != nil)
        #expect(widgets.url(forResource: "HeroBlink1-\(coat.rawValue)", withExtension: "webp") == nil)
        #expect(widgets.url(forResource: "HeroEar1-\(coat.rawValue)", withExtension: "webp") == nil)
    }
}
