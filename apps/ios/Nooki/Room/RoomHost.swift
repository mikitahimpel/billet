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
        let _ = controller.probe.hostBody()
        RoomStage(input: input, controller: controller)
    }
}

/// What is drawn for one input: the City's window under the room and the room itself while it can be seen.
private struct RoomStage: View {
    let input: RoomInput
    let controller: RoomController

    var body: some View {
        let _ = controller.probe.stageBody()
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
            } else if input.visibility == .visible || input.visibility == .parked,
                let scene = controller.scene(for: input.scene)
            {
                // Under another tab or a sheet the view stays, at full opacity with the room's root disabled: making a
                // new RealityView on the way back holds the main thread for a frame of 0.3 to 1.5 s, and one at
                // opacity 0 stalls about 1 s at a time while its drawables wait (#417). Under the canvas or in the
                // background, where the view leaves the window, it goes; the scenes stay loaded, so coming back makes
                // a new view.
                let parked = input.visibility == .parked
                DioramaView(scene: scene, paused: parked || controller.corner != nil, petPulse: controller.petPulse) {
                    controller.petted()
                }
                .allowsHitTesting(!parked && controller.game == nil)
                .accessibilityHidden(parked)
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
