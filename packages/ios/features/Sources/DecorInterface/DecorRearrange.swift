import Foundation

extension DecorLayout {
  /// What turning a piece comes to.
  public enum Turn: Equatable, Sendable {
    /// It turned where it stands.
    case turned(DecorLayout)
    /// The turned footprint did not fit there, so it turned at the nearest spot that does.
    case slid(DecorLayout, to: Placement)
    /// Nothing in the room fits it turned: the player may put it away.
    case noRoom
  }

  /// A turn (a quarter by default, 45 degrees for `byEighths: 1`) that never fails for lack of room while any spot fits the turned piece. A wall piece has
  /// no turn and answers nil.
  public func turning(_ item: String, byEighths eighths: Int = 2, in room: DecorRoom = .home)
    -> Turn?
  {
    guard let placement = placement(of: item), placement.surface == .floor else { return nil }
    let turned = placement.turned(byEighths: eighths)
    if accepts(turned, in: room) { return .turned(putting(turned)) }
    if let spot = nearestFit(to: turned, in: room) { return .slid(putting(spot), to: spot) }
    return .noRoom
  }

  /// What dropping a piece on a spot comes to.
  public enum Drop: Equatable, Sendable {
    case fits(DecorLayout)
    /// Two pieces changed places.
    case swapped(DecorLayout, with: String)
    /// The piece stands there and the one that was in the way moved aside.
    case nudged(DecorLayout, other: String, to: Placement)
    /// It did not fit where it was let go, so it stands at the nearest spot that does, within `slideReach`.
    case slid(DecorLayout, to: Placement)
    case rejected(Verdict)
  }

  /// The pieces on the same surface that `placement` would stand on.
  public func blockers(of placement: Placement) -> [String] {
    guard let item = DecorItem.item(shopID: placement.item),
      let span = Self.span(of: placement, item: item)
    else { return [] }
    return allPlacements.filter { $0.space == placement.space }.compactMap { other in
      guard other.item != placement.item, other.surface == placement.surface,
        let otherItem = DecorItem.item(shopID: other.item),
        let otherSpan = Self.span(of: other, item: otherItem)
      else { return nil }
      if placement.surface == .floor, item.isFlat || otherItem.isFlat { return nil }
      return span.overlaps(otherSpan) ? other.item : nil
    }
  }

  /// Puts a piece on `placement`: where it fits it stands; on one other piece it swaps with it when both fit
  /// in each other's place, else moves it aside to the nearest spot that fits; otherwise it slides to the
  /// nearest spot that fits within `slideReach` cells, else is rejected.
  public func dropping(_ placement: Placement, in room: DecorRoom = .home) -> Drop {
    let verdict = verdict(placement, in: room)
    if verdict == .fits { return .fits(putting(placement)) }
    if let exchanged = exchanging(placement, verdict: verdict, in: room) { return exchanged }
    if let spot = nearestFit(to: placement, in: room),
      Self.cells(from: placement, to: spot) <= Self.slideReach
    {
      return .slid(putting(spot), to: spot)
    }
    return .rejected(verdict)
  }

  /// A swap with the one piece in the way, or that piece moved aside; nil when neither works.
  private func exchanging(_ placement: Placement, verdict: Verdict, in room: DecorRoom) -> Drop? {
    let blocking = blockers(of: placement)
    guard verdict == .occupied, blocking.count == 1, let other = self.placement(of: blocking[0]),
      let mine = self.placement(of: placement.item)
    else { return nil }

    if mine.surface == other.surface {
      let lifted = storing(placement.item)
      let there = other.moved(to: mine.surface, u: mine.u, v: mine.v)
      if lifted.accepts(there, in: room) {
        let swapped = lifted.putting(there)
        if swapped.accepts(placement, in: room) {
          return .swapped(swapped.putting(placement), with: other.item)
        }
      }
    }

    let aside = storing(other.item).putting(placement)
    if storing(other.item).accepts(placement, in: room),
      let spot = aside.nearestFit(to: other, in: room)
    {
      return .nudged(aside.putting(spot), other: other.item, to: spot)
    }
    return nil
  }

  /// A room as a pair that never arranged it has it: its own furniture at home. The living room also takes
  /// every bought piece that is not in the bedroom, as it settles; the bedroom's own go to the closet. The
  /// other room is left as it is.
  public func reset(owned: Set<String>, in room: DecorRoom = .home) -> DecorLayout {
    func isOwn(_ id: String, of space: DecorSpace) -> Bool {
      DecorItem.item(shopID: id)?.base?.space == space
    }
    let others = placements.filter { $0.space != room.space }
    switch room.space {
    case .living:
      let away = stored.filter { isOwn($0, of: .bedroom) }
      return DecorLayout(placements: others, stored: DecorItem.starters.union(away))
        .settled(owned: owned, in: room)
    case .bedroom:
      let bought = placements.filter { $0.space == .bedroom && !isOwn($0.item, of: .bedroom) }
        .map(\.item)
      let kept = stored.filter { !isOwn($0, of: .bedroom) }
      return DecorLayout(placements: others, stored: kept.union(bought))
    }
  }
}
