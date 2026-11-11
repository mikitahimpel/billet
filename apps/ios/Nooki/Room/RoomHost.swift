import FeatureGames
import GamesInterface
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
            .onChange(of: PartnerSight(input), initial: true) { _, sight in
                controller.partnerSeen(here: sight.here, visible: sight.visible)
            }
    }
}

/// The part of the input the cat's notice of the partner reads.
private struct PartnerSight: Equatable {
    let here: Bool
    let visible: Bool

    init(_ input: RoomInput) {
        here = input.partnerHere
        visible = input.visibility == .visible
    }
}

/// What is drawn for one input: the City's window under the room and the room itself while it can be seen.
private struct RoomStage: View {
    let input: RoomInput
    let controller: RoomController

    private var visible: Bool { input.visibility == .visible }

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
            } else if let scene = controller.scene(for: input.scene) {
                // One view for the app's life. A RealityView that goes away takes the GPU side of what it drew with
                // it a few seconds later, so a room moved into a new one after that draws nothing until relaunch.
                // While no room can be seen it holds an empty one, paused and transparent. A RealityView renders every
                // frame while it exists, so it also shrinks to one point: each of those frames is next to nothing.
                // On its own renderer the view is never freed and its frames stop while it is not shown, so it stays
                // full size and keeps its room.
                let loop = controller.loop
                DioramaView(scene: visible || loop != nil ? scene : controller.offStage,
                            paused: !visible || controller.corner != nil, petPulse: controller.petPulse,
                            showsBubble: !input.decor.isArranging, rendering: input.rendering, loop: loop) {
                    controller.petted()
                }
                .frame(width: visible || loop != nil ? nil : 1, height: visible || loop != nil ? nil : 1)
                .allowsHitTesting(visible && controller.game == nil)
                .opacity(visible ? 1 : 0)
                .accessibilityHidden(true)
                .modifier(RoomTapCounter())
                .ignoresSafeArea()

                if visible, controller.game == nil { CatVoice(name: input.catName, controller: controller) }
                if visible, controller.game == nil, input.decor.isArranging { DecorTouchLayer(controller: controller) }
            }
        }
        // The room's view no longer drives a room it doesn't show; the next look starts it again.
        .onChange(of: visible) { _, visible in
            if !visible { controller.stop() }
        }
        .onChange(of: input.decor, initial: true) { _, decor in controller.showDecor(decor) }
        .onChange(of: input.motes, initial: true) { _, motes in controller.showMotes(motes) }
        .onChange(of: input.sway, initial: true) { _, sway in controller.setSway(sway) }
        // Her status is read once a second only while she can be seen; under a cover or a sheet that hides her it
        // waits, and the first look back reads it at once.
        .task(id: input.visibility == .visible && controller.hasHome) {
            guard input.visibility == .visible, controller.hasHome else { return }
            await controller.watchStatus()
        }
    }
}

/// The room as VoiceOver meets it: one element named for her, saying what she does, that pets her on a double tap.
/// Its own view, so her status changing re-evaluates only this and never the stage.
private struct CatVoice: View {
    let name: String
    let controller: RoomController

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue(controller.status.spoken)
            .accessibilityHint("Double tap to pet her.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { controller.petted() }
            .accessibilityAction(named: "Treat or play") { controller.careAsked() }
            .accessibilityIdentifier("cat")
    }
}

/// The mini-game over the room, while one is played: its own scene in the corner, or the room itself for the laser.
/// The shell puts it over its own chrome, which a game hides.
struct RoomGameLayer: View {
    let controller: RoomController

    var body: some View {
        if let game = controller.game, let room = controller.gameRoom {
            let switcher = GameSceneSwitch(
                options: GameScenery.options(for: game), selected: controller.scenery,
                select: { controller.showScenery($0) })
            if controller.playsInCorner {
                if let corner = controller.corner {
                    GameView(
                        session: GameSession(game: game, room: corner, catLife: controller.catLife),
                        corner: corner, scenes: switcher
                    ) { controller.endGame() }
                    .id(GameKey(game: game, inCorner: true))
                    .transition(.opacity)
                }
            } else {
                GameView(session: GameSession(game: game, room: room, catLife: controller.catLife), scenes: switcher) {
                    controller.endGame()
                }
                .id(GameKey(game: game, inCorner: false))
                .transition(.opacity)
            }
        }
    }

    /// A game keeps its session while it moves from one corner to another, and starts over between the room and one.
    private struct GameKey: Hashable {
        let game: MiniGame
        let inCorner: Bool
    }
}
