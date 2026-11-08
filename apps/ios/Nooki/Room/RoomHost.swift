import RoomInterface
import SwiftUI

/// The only view the shell has of the room. It takes a value and a controller used for its identity, and so
/// re-evaluates only when the input changes (`.equatable()`); the room's own state is read by the stage inside,
/// where a tick can't reach the shell.
struct RoomHost: View, Equatable {
    let input: RoomInput
    let controller: RoomController

    static func == (a: Self, b: Self) -> Bool { a.input == b.input && a.controller === b.controller }

    var body: some View {
        let _ = RoomProbe.hostBody()
        RoomStage(input: input, controller: controller)
    }
}

/// What is drawn for one input: the City's window under the room and the room itself while it can be seen.
private struct RoomStage: View {
    let input: RoomInput
    let controller: RoomController

    var body: some View {
        let _ = RoomProbe.stageBody()
        ZStack {
            // The City window's view, seen through the hole in the room's wall; never takes a touch.
            if !controller.isStandIn, input.scene == .city, input.visibility != .hidden,
                let window = controller.cityWindowView
            {
                CityWindowLayer(view: window)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .ignoresSafeArea()
            }

            if controller.isStandIn {
                // A stand-in for the room under the UI tests, which cannot draw RealityKit on CI's virtual Macs.
                Color.clear
                    .contentShape(.rect)
                    .allowsHitTesting(input.visibility == .visible && controller.game == nil)
                    .modifier(RoomTapCounter())
                    .ignoresSafeArea()
            } else if input.visibility == .visible, let scene = controller.scene(for: input.scene) {
                // Only while the room can be seen: a paused RealityView left in place under the Shop, Moments, Us or
                // a cover still runs its render loop and composites a full-screen layer every frame. The scenes stay
                // loaded, so coming back only makes a new view for one.
                DioramaView(scene: scene, paused: controller.corner != nil, petPulse: controller.petPulse) {
                    controller.petted()
                }
                .allowsHitTesting(controller.game == nil)
                .modifier(RoomTapCounter())
                .ignoresSafeArea()
            }
        }
    }
}

/// The mini-game over the room, while one is played: its own scene in the corner, or the room itself for the laser.
/// The shell puts it over its own chrome, which a game hides.
struct RoomGameLayer: View {
    let controller: RoomController

    var body: some View {
        if let game = controller.game, let room = controller.gameRoom {
            if RoomController.usesCorner(game), !controller.isStandIn {
                if let corner = controller.corner {
                    GameView(
                        session: GameSession(game: game, room: corner, catEvents: controller.catEvents),
                        corner: corner
                    ) { controller.endGame() }
                    .id(game)
                    .transition(.opacity)
                }
            } else {
                GameView(session: GameSession(game: game, room: room, catEvents: controller.catEvents)) {
                    controller.endGame()
                }
                .id(game)
                .transition(.opacity)
            }
        }
    }
}
