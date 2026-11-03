import RealityKit
import Testing

@testable import PetSceneReality

/// The marker under a piece being moved shows over the rugs, never in or under them.
@MainActor
@Suite struct DecorMarkerTests {
  @Test func theStyledRoomsMarkerFloatsOverEveryRug() {
    for kind in [GenzPiece.Kind.patternRug, .roundRug, .checkeredRug] {
      let top = GenzKit().build(GenzPiece(kind)).visualBounds(relativeTo: nil).max.y
      #expect(GenzRoom.markerHeight > top + 0.01, "\(kind) tops out at \(top)")
    }
  }

  @Test func nookisMarkerFloatsOverTheRug() async throws {
    let rug = NookiFurniture.items.first { $0.name == "Item_rug" }
    let placed = try #require(rug)
    let model = try await NookiAssets().model(placed.name)
    let bounds = model.visualBounds(relativeTo: nil)
    let width = try #require(placed.width)
    let top = placed.position.y + bounds.extents.y * width / max(bounds.extents.x, bounds.extents.z)
    #expect(NookiRenovation.markerHeight > top + 0.003, "the rug tops out at \(top)")
  }
}
