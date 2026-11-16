import Design
import SwiftUI
import Testing
@testable import Billet

/// A hint's card sits in Home's own layer, across it inside the gutters, on the side of its control the arrow edge
/// says, its arrow toward the control's middle.
@MainActor
struct HintPlacementTests {
    private let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)

    @Test func aCardWithItsArrowBelowSitsAboveTheControl() {
        let plus = CGRect(x: 330, y: 790, width: 56, height: 56)
        let placement = HintPlacement(spot: HintSpot(frame: plus, edge: .bottom), bounds: bounds)
        #expect(placement.pointer.edge == .bottom)
        #expect(placement.inset == bounds.maxY - plus.minY + Space.s * 2)
        #expect(placement.width == bounds.width - 2 * Space.l)
    }

    @Test func aCardWithItsArrowAboveSitsBelowTheControl() {
        let roomSwitch = CGRect(x: 100, y: 120, width: 200, height: 44)
        let placement = HintPlacement(spot: HintSpot(frame: roomSwitch, edge: .top), bounds: bounds)
        #expect(placement.pointer.edge == .top)
        #expect(placement.inset == roomSwitch.maxY + Space.s * 2)
        #expect(abs(placement.pointer.position - 0.5) < 0.01)
    }

    @Test func theArrowFollowsTheControlAndStopsAtTheCorners() {
        func position(_ x: CGFloat) -> CGFloat {
            let control = CGRect(x: x - 20, y: 800, width: 40, height: 40)
            return HintPlacement(spot: HintSpot(frame: control, edge: .bottom), bounds: bounds).pointer.position
        }
        #expect(position(10) == 0)
        #expect(position(392) == 1)
        #expect(position(120) < position(300))
    }

    @Test func aLayerBelowTheTopOfTheScreenMeasuresFromItsOwnEdges() {
        let inset = CGRect(x: 0, y: 62, width: 402, height: 778)
        let plus = CGRect(x: 330, y: 760, width: 56, height: 56)
        let placement = HintPlacement(spot: HintSpot(frame: plus, edge: .bottom), bounds: inset)
        #expect(placement.inset == inset.maxY - plus.minY + Space.s * 2)
        let header = CGRect(x: 100, y: 80, width: 200, height: 44)
        let below = HintPlacement(spot: HintSpot(frame: header, edge: .top), bounds: inset)
        #expect(below.inset == header.maxY - inset.minY + Space.s * 2)
    }
}

/// A still room writes its pivot only when its turn changes, except for a moment after its view is shown again.
struct RedrawWindowTests {
    @Test func aStillRoomWritesNothingUntilTheWindowOpens() {
        var window = RedrawWindow()
        #expect(!window.writes(at: 3, changed: false))
        #expect(window.writes(at: 3, changed: true))
        window.open(at: 10)
        #expect(window.writes(at: 10.1, changed: false))
        #expect(window.writes(at: 10 + RedrawWindow.seconds, changed: false))
        #expect(!window.writes(at: 10 + RedrawWindow.seconds + 0.01, changed: false))
    }
}
