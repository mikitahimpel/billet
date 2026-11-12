import SwiftUI
import Testing
@testable import Billet

/// The room's view is a point while no room can be seen, and changes size only while the app is in front.
struct RoomShrinkTests {
    @Test func inFrontItFollowsWhatIsWanted() {
        #expect(RoomViewSize.isShrunk(wanted: true, inFront: false, phase: .active))
        #expect(!RoomViewSize.isShrunk(wanted: false, inFront: true, phase: .active))
    }

    @Test func leavingTheFrontKeepsTheSizeItHad() {
        for phase in [ScenePhase.inactive, .background] {
            #expect(!RoomViewSize.isShrunk(wanted: true, inFront: false, phase: phase), "full size stays full")
            #expect(RoomViewSize.isShrunk(wanted: false, inFront: true, phase: phase), "a point stays a point")
        }
    }
}
