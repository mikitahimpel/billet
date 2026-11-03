import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzSillTests {
  @Test func theFirstWindowSeatsCatLivesOnTheSill() throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .original))
    let top = try #require(layout.catSurface)
    #expect(top.max.y <= GenzLayout.Seat.sillDepth)
    #expect(top.min.y >= 0)
    let home = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    #expect(home == simd_clamp(home, top.min, top.max))
  }

  @Test func theFurnishedSetsKeepTheCatOnTheirOwnSeat() throws {
    for furniture in [RoomFurniture.cosyNook, .retroDen] {
      let layout = try #require(GenzLayout.of(.windowSeat, furniture: furniture))
      #expect(layout.catTop == nil)
      #expect((layout.catSurface?.max.y ?? 0) > GenzLayout.Seat.sillDepth)
    }
  }

  @Test func nothingOnTheDaybedReachesIntoTheSill() throws {
    let layout = try #require(GenzLayout.of(.windowSeat, furniture: .original))
    let bed = try #require(layout.pieces.first { $0.piece.kind == .daybed })
    let (holder, _) = GenzRoom.placed(bed, kit: GenzKit())
    let sillUnderside = GenzLayout.Seat.window.z0 - 0.12
    SceneParts.visit(holder) { entity in
      guard let model = entity as? ModelEntity else { return }
      let bounds = model.visualBounds(relativeTo: nil)
      guard bounds.max.y > sillUnderside + 0.001 else { return }
      #expect(bounds.min.z >= GenzLayout.Seat.sillDepth, "\(bounds) reaches into the sill")
    }
  }
}
