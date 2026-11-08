import RoomInterface
import Testing
@testable import Billet

/// When the room's view stays mounted: a new RealityView on the way back freezes the screen, and one out of the
/// window stalls on its drawables.
@MainActor
struct RoomVisibilityTests {
    private func visibility(onScreen: Bool = false, showsRoom: Bool = false, drawing: Bool = false,
                            background: Bool = false) -> RoomVisibility {
        HomeView.roomVisibility(onScreen: onScreen, showsRoom: showsRoom, drawing: drawing, background: background)
    }

    @Test func theWorldOnScreenIsVisible() {
        #expect(visibility(onScreen: true, showsRoom: true) == .visible)
    }

    @Test func anotherTabParksTheRoom() {
        #expect(visibility() == .parked)
    }

    @Test func aSheetOverTheWorldParksTheRoom() {
        #expect(visibility(showsRoom: true) == .parked)
    }

    @Test func theCanvasTakesTheRoomDown() {
        #expect(visibility(showsRoom: true, drawing: true) == .covered)
        #expect(visibility(drawing: true) == .hidden)
    }

    @Test func theBackgroundTakesTheRoomDown() {
        #expect(visibility(showsRoom: true, background: true) == .covered)
        #expect(visibility(background: true) == .hidden)
    }
}
