import Pet
import Testing

@testable import PetSceneReality

@MainActor
@Suite struct GenzCatPathTests {
  private static var layouts: [GenzLayout] {
    RoomFurniture.allCases.map { GenzLayout.of($0) }
      + [RoomFurniture.cosyNook, .retroDen].map { GenzLayout.of($0, idolProps: true) }
  }

  @Test func theCatsPlaceIsClearOfWhatStandsOnItsTop() {
    for layout in Self.layouts {
      let home = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
      #expect(!layout.catClutter.contains { $0.contains(home) }, "\(layout.key)")
    }
  }

  /// Slow, so it gives way to the other tests' rooms once a row, and checks the generated props'
  /// rooms on a coarser grid.
  @Test func nowhereTheCatIsSentIsAmongClutter() async throws {
    for layout in Self.layouts {
      let surface = try #require(layout.catSurface)
      let step: Float = layout.idolProps ? 0.4 : 0.2
      for x in stride(from: surface.min.x, through: surface.max.x, by: step) {
        await Task.yield()
        for y in stride(from: surface.min.y, through: surface.max.y, by: step) {
          let spot = layout.onCatSurface([x, y])
          #expect(
            !layout.catClutter.contains { $0.contains(spot) }, "\(layout.key) sends it to \(spot)")
        }
      }
    }
  }

  @Test func aWalkAlongTheSeatStopsShortOfTheCardigan() throws {
    let layout = GenzLayout.of(.cosyNook)
    let cardigan = try #require(layout.pieces.first { $0.piece.kind == .cardigan })
    // In front of the pillows, along the seat.
    let home = SIMD2(layout.cat.spot.x, 1.1)
    let reach = layout.catReach(from: home, to: [0.9, home.y])
    let cardiganEnd = cardigan.centre.x + cardigan.piece.kind.size.x / 2
    #expect(reach.x > cardiganEnd + layout.cat.length * 0.4)
    #expect(reach.x < home.x)
    // Along the pillows, it does not walk into the first one.
    let pillowEnd = try #require(
      layout.catObstacles.filter(\.builtIn).map(\.box).map { $0.centre.x + $0.half.x }.max())
    let alongPillows = SIMD2(layout.cat.spot.x, layout.cat.spot.y)
    #expect(layout.catReach(from: alongPillows, to: [0.9, alongPillows.y]).x > pillowEnd)
    let legs = [CatTrip.Leg.walk(to: [0.9, home.y], speed: 1)].clear(of: layout, from: home)
    guard case .walk(let to, _, _) = legs.first else {
      Issue.record("the walk is kept")
      return
    }
    #expect(to == reach)
  }

  @Test func thePlantOnTheDaybedIsInTheWayButThePhoneIsNot() throws {
    let layout = GenzLayout.of(.original)
    let plant = try #require(layout.pieces.first { $0.piece.kind == .snakePlant })
    let phone = try #require(layout.pieces.first { $0.piece.kind == .phoneOnCharger })
    #expect(layout.catClutter.contains { $0.contains([plant.centre.x, plant.centre.y]) })
    #expect(!layout.catClutter.contains { $0.contains([phone.centre.x, phone.centre.y]) })
  }
}
