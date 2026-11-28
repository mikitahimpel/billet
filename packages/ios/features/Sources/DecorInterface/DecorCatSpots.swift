import Foundation

/// Where the cat can go to use a placed piece: a floor spot beside it she walks to, and for a seat the
/// top she climbs onto.
public struct CatSpotPlan: Equatable, Sendable {
  public let use: CatUse
  public let item: String
  /// On the floor, outside the piece and its margin, reachable from her bed.
  public let approach: Occupancy.Point
  /// Where she sits on a seat, with its height in metres; nil for a post, which she stands beside.
  public let top: (point: Occupancy.Point, height: Double)?

  public static func == (a: CatSpotPlan, b: CatSpotPlan) -> Bool {
    a.use == b.use && a.item == b.item && a.approach.x == b.approach.x
      && a.approach.z == b.approach.z
      && a.top?.point.x == b.top?.point.x && a.top?.point.z == b.top?.point.z
      && a.top?.height == b.top?.height
  }
}

extension DecorLayout {
  /// One spot for each use the layout has a piece for, the first by name. A piece she cannot get to
  /// from her bed, with the others in the way, gives none.
  public func catSpots(in room: DecorRoom = .home) -> [CatSpotPlan] {
    let occupancy = occupancy(in: room)
    var plans: [CatSpotPlan] = []
    var seen = Set<CatUse>()
    for placement in placements.filter({ $0.space == room.space }).sorted(by: { $0.item < $1.item })
    {
      guard placement.surface == .floor, let item = DecorItem.item(shopID: placement.item),
        let use = item.cat, !seen.contains(use),
        let span = Self.span(of: placement, item: item),
        let approach = Self.approach(to: span, in: occupancy, from: room.spawn)
      else { continue }
      seen.insert(use)
      let top: (Occupancy.Point, Double)? =
        switch use {
        case .post: nil
        case .sofa, .windowSeat, .catBed: ((span.x, span.z), item.height * 0.9)
        case .crate: ((span.x, span.z), item.height * 0.6)
        }
      plans.append(CatSpotPlan(use: use, item: item.id, approach: approach, top: top))
    }
    return plans.sorted { $0.use.rawValue < $1.use.rawValue }
  }

  /// The free cell beside `span` she can walk to from `spawn`, with nothing else standing between it and the
  /// piece. Far enough off that facing the piece her head is clear of it, and where no such cell is free, a hand's
  /// width off it; square to a side before off a corner, which is a long way to jump from; then nearest first.
  static func approach(to span: Span, in occupancy: Occupancy, from spawn: Occupancy.Point)
    -> Occupancy.Point?
  {
    let handsWidth = 0.07
    for gap in [Occupancy.noseReach + 0.01, handsWidth] {
      // Counted in whole cells outward, so the grid never brings her nearer than the gap.
      let dx = (((span.halfX + gap) / DecorGrid.step) - 0.001).rounded(.up) * DecorGrid.step
      let dz = (((span.halfZ + gap) / DecorGrid.step) - 0.001).rounded(.up) * DecorGrid.step
      let sides: [Occupancy.Point] = [
        (span.x, span.z + dz), (span.x, span.z - dz), (span.x + dx, span.z), (span.x - dx, span.z),
      ]
      let corners: [Occupancy.Point] = [
        (span.x + dx, span.z + dz), (span.x - dx, span.z + dz), (span.x + dx, span.z - dz),
        (span.x - dx, span.z - dz),
      ]
      for around in [sides, corners] {
        let onGrid: [Occupancy.Point] = around.map {
          (DecorGrid.metres(DecorGrid.cell($0.x)), DecorGrid.metres(DecorGrid.cell($0.z)))
        }
        let open = onGrid.filter {
          !occupancy.isBlocked(at: $0) && occupancy.connects(from: spawn, to: [$0])
            && hypot($0.x - span.x, $0.z - span.z) <= longestJumpUp
            && !occupancy.crossesPiece(from: $0, to: span.nearest(to: $0), otherThan: span)
        }
        let spot = open.min {
          hypot($0.x - spawn.x, $0.z - spawn.z) < hypot($1.x - spawn.x, $1.z - spawn.z)
        }
        if let spot { return spot }
      }
    }
    return nil
  }

  /// The longest way along the floor, in metres, between the middle of a piece she sits on and where she takes
  /// off for it or lands from it.
  static let longestJumpUp = 0.4
}
