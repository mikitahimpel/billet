import Pet
import SwiftUI
import Testing
@testable import Billet

/// The cat sheet shows her four needs as gauges, met, in the middle and low, each with its care where it has one.
@MainActor @Suite(.serialized) struct NeedGridTests {
    @Test(arguments: [1.0, 0.5, 0.15])
    func fourTilesShowAtEveryLevelAndTheCaresAreOnThem(level: Double) {
        let grid = NeedGrid(name: "Mochi", pronouns: .she, needs: PetNeeds(all: level), asleep: false, care: { _ in })
        let layout = HostedLayout(ScrollView { grid.padding(16) }, phone: .se)
        layout.settle(0.5)
        let labels = Set(layout.elements().map(\.label))
        for need in ["Full", "Rested", "Playful", "Loved"] {
            #expect(labels.contains(need), "the \(need) tile shows at \(level)")
        }
        let ids = Set(layout.elements().map(\.identifier))
        for care in ["Feed", "Play", "Pet"] {
            #expect(ids.contains(care), "the \(care) care shows at \(level)")
        }
        let tiles = ["Full", "Rested", "Playful", "Loved"].compactMap { layout.element(label: $0)?.frame }
        #expect(tiles.allSatisfy { layout.bounds.contains($0) || $0.maxX <= layout.bounds.maxX }, "the tiles sit inside the width at \(level)")
    }
}
