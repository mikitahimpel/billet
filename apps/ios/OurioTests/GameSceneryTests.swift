import FeatureGames
import GamesInterface
import Testing
@testable import Billet

/// The game's scene switch on the stand-in controller, where no corner is built.
@MainActor
struct GameSceneryTests {
    @Test func aGameStartsInItsFirstSceneAndMovesOnlyToOnesItOffers() {
        let controller = RoomController(usesStandIn: true)
        controller.play(.brush)
        #expect(controller.scenery == .rug)
        controller.showScenery(.kitchen)
        #expect(controller.scenery == .kitchen)
        controller.showScenery(.room)
        #expect(controller.scenery == .kitchen, "brush is never played in the room")
        controller.endGame()
        controller.play(.feed)
        #expect(controller.scenery == .kitchen)
        controller.showScenery(.garden)
        #expect(controller.scenery == .kitchen, "feed and water have the kitchen only")
        #expect(!controller.playsInCorner, "the stand-in has no corner")
    }

    @Test func theSceneSwitchDoesNothingWithoutAGame() {
        let controller = RoomController(usesStandIn: true)
        controller.showScenery(.garden)
        #expect(controller.game == nil)
        #expect(controller.scenery == .room)
    }

    @Test func aGameComesBackToTheScenePickedLastTime() {
        let controller = RoomController(usesStandIn: true)
        controller.play(.laser)
        #expect(controller.scenery == .kitchen)
        controller.showScenery(.room)
        controller.endGame()
        controller.play(.brush)
        #expect(controller.scenery == .rug, "each game remembers its own")
        controller.endGame()
        controller.play(.laser)
        #expect(controller.scenery == .room)
    }
}
