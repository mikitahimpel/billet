import Pet
import Testing
import simd

@testable import PetSceneReality

/// The seat's pillows move (decorating slides them along the backrest), and wherever they are
/// and wherever the cat settles, they slide aside so no cat's body, as it sits, loafs and sleeps
/// curled up, is ever in one. Sampled: each pillow every 0.6 along the seat, the cats by their
/// resting bodies, rest spots along the seat. The checks are arithmetic, so it runs in seconds.
@MainActor
@Suite struct GenzCatPillowTests {
  /// The rooms whose seat has pillows of its own to move.
  private var layouts: [(String, GenzLayout)] {
    (RoomFurniture.allCases.map { ("windowSeat \($0)", GenzLayout.of($0)) }
      + [("windowSeat cosyNook idol", GenzLayout.of(.cosyNook, idolProps: true))])
      .filter { !$0.1.catPillows.isEmpty }
  }

  /// Every cat the picker offers, one of each resting body.
  private var cats: [CatModel] {
    var seen: [GenzCatShape] = []
    return CatModel.allCases.filter(\.isListed).filter { model in
      guard !seen.contains(model.footprint.resting) else { return false }
      seen.append(model.footprint.resting)
      return true
    }
  }

  /// The cats with the widest and the smallest resting bodies.
  private var extremes: [CatModel] {
    let all = cats
    let byRadius = all.sorted { $0.footprint.resting.radius < $1.footprint.resting.radius }
    return [byRadius.first, byRadius.last].compactMap { $0 }
  }

  /// Each pillow slid along the seat every 0.6, the others where they were built, where it does
  /// not land on another pillow; and as built.
  private func arrangements(_ layout: GenzLayout) -> [(String, GenzLayout)] {
    guard let surface = layout.catSurface else { return [] }
    var out: [(String, GenzLayout)] = [("as built", layout)]
    for index in layout.catPillows {
      let kind = layout.pieces[index].piece.kind
      let half = layout.pillowSeatBox(index).half.x
      for x in stride(from: surface.min.x + half, through: surface.max.x - half, by: 0.6) {
        var moved = layout
        moved.pieces[index].centre.x = x
        let mine = moved.pillowSeatBox(index)
        let others = moved.catPillows.filter { $0 != index }.map(moved.pillowSeatBox)
        guard !others.contains(where: { $0.overlaps(mine) }) else { continue }
        out.append(("\(kind) at x \(x)", moved))
      }
    }
    return out
  }

  /// Where the cat may settle: along the seat at the back, where its home is, and the middle.
  private func restSpots(_ layout: GenzLayout) -> [SIMD2<Float>] {
    guard let surface = layout.catSurface else { return [] }
    let home = SIMD2(layout.cat.spot.scene.x, layout.cat.spot.scene.z)
    let middle = (surface.min.y + surface.max.y) / 2
    return [home]
      + stride(from: surface.min.x + 0.6, through: surface.max.x - 0.6, by: 0.8).flatMap {
        [SIMD2($0, home.y), SIMD2($0, middle)]
      }
  }

  /// Points over the resting body's outline and middle line at `spot` facing `heading`.
  private func outline(_ layout: GenzLayout, at spot: SIMD2<Float>, heading: Float)
    -> [SIMD2<Float>]
  {
    let shape = layout.catBody.resting
    let spine = shape.spine(at: spot, heading: heading, length: layout.cat.length)
    let radius = shape.radius * layout.cat.length
    return spine
      + spine.flatMap { centre in
        (0..<16).map { k in
          let angle = Float(k) / 16 * 2 * .pi
          return centre + SIMD2(cos(angle), sin(angle)) * radius
        }
      }
  }

  @Test(.timeLimit(.minutes(1)))  // A few seconds; CI's runners are slower.
  func everyCatRestsClearOfThePillowsWhereverTheyAre() async throws {
    let rooms = layouts
    #expect(!rooms.isEmpty)
    var checked = 0
    for (name, base) in rooms {
      let surface = try #require(base.catSurface)
      for (arranged, layout) in arrangements(base) {
        await Task.yield()
        // Every cat's body on the pillows as built; the widest and the smallest wherever the
        // pillows are moved, as the bodies between part them between.
        for model in arranged == "as built" ? cats : extremes {
          var shown = layout
          shown.catBody = model.footprint
          for spot in restSpots(shown) {
            for heading in [Float(0), .pi / 2, .pi, -.pi / 2] {
              // Where the pillows cannot part, the cat settles along the seat where they can.
              let spot = shown.pillowRoom(near: spot, heading: heading)
              let nudges = try #require(
                shown.pillowNudges(clearOf: spot, heading: heading),
                "\(name), \(arranged): \(model) finds no room near \(spot) facing \(heading)")
              var after = shown
              for (index, x) in nudges { after.pieces[index].centre.x = x }
              checked += 1
              let pillows = after.catPillows.map(after.pillowBox)
              let hit = outline(after, at: spot, heading: heading).first { point in
                pillows.contains { $0.distance(to: point) <= 0 }
              }
              let place = "\(name), \(arranged): \(model) at \(spot) facing \(heading)"
              #expect(hit == nil, "\(place) is in a pillow at \(String(describing: hit))")
              // The pillows stay on the seat, and apart.
              let seated = after.catPillows.map(after.pillowSeatBox)
              for (i, box) in seated.enumerated() {
                #expect(
                  box.centre.x - box.half.x >= surface.min.x - 1e-3
                    && box.centre.x + box.half.x <= surface.max.x + 1e-3,
                  "\(place): a pillow off the seat at \(box.centre.x)")
                for other in seated[(i + 1)...] where box.overlaps(other, tolerance: 0.01) {
                  Issue.record("\(place): pillows at \(box.centre.x) and \(other.centre.x) overlap")
                }
              }
              if hit != nil { return }
            }
          }
        }
      }
    }
    #expect(checked > 1000)
  }

  @Test func eachCatHasItsOwnMeasuredBody() {
    let unmeasured = (GenzCatShape.widestStanding, GenzCatShape.widestResting)
    for model in CatModel.allCases where model.isListed && model != .splatGinger {
      let body = model.footprint
      #expect(body != unmeasured, "\(model) has no measured body")
      // Curled up asleep or loafing, a cat is round: wider than it stands.
      #expect(body.resting.half >= body.standing.half, "\(model)")
      #expect(body.resting.half <= GenzCatShape.widestResting.half, "\(model)")
    }
  }

  @Test func aCatClearOfThePillowsMovesNone() throws {
    let layout = GenzLayout.of(.cosyNook)
    let surface = try #require(layout.catSurface)
    // Out in front of the pillows, in the seat's middle, facing along it.
    let spot = SIMD2((surface.min.x + surface.max.x) / 2, surface.max.y + layout.cat.length * 2)
    #expect(layout.pillowNudges(clearOf: spot, heading: .pi / 2)?.isEmpty == true)
  }
}
