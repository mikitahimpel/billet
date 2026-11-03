import RealityKit
import Testing

@testable import PetSceneReality

/// The marker under a piece being moved shows over the rugs, never in or under them.
@MainActor
@Suite struct DecorMarkerTests {
  @Test func theStyledRoomsMarkerFloatsOverEveryRug() {
    for kind in [GenzPiece.Kind.patternRug, .roundRug] {
      let top = GenzKit().build(GenzPiece(kind)).visualBounds(relativeTo: nil).max.y
      #expect(GenzRoom.markerHeight > top + 0.01, "\(kind) tops out at \(top)")
    }
  }

}
