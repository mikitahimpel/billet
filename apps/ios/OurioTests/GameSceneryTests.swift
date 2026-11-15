import FeatureGames
import GamesInterface
import Testing
@testable import Billet

/// Each game opens in its own scene, on the stand-in controller, where no corner is built.
@MainActor
struct GameSceneryTests {
    @Test func aGameOpensInItsOwnScene() {
        let controller = RoomController(usesStandIn: true)
        controller.play(.brush)
        #expect(controller.scenery == .rug)
        #expect(!controller.playsInCorner, "the stand-in has no corner")
        controller.endGame()
        controller.play(.feed)
        #expect(controller.scenery == .kitchen)
        controller.endGame()
        controller.play(.laser)
        #expect(controller.scenery == .room, "the laser is only ever played in the living room")
    }
}
