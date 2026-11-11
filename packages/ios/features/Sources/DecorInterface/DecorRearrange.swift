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

  /// A quarter turn that never fails for lack of room while any spot fits the turned piece. A wall piece has
  /// no turn and answers nil.
  public func turning(_ item: String, in room: DecorRoom = .home) -> Turn? {
    guard let placement = placement(of: item), placement.surface == .floor else { return nil }
    let turned = placement.turned
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
    case rejected(Verdict)
  }

  /// The pieces on the same surface that `placement` would stand on.
  public func blockers(of placement: Placement) -> [String] {
    guard let item = DecorItem.item(shopID: placement.item),
      let span = Self.span(of: placement, item: item)
    else { return [] }
    return allPlacements.compactMap { other in
      guard other.item != placement.item, other.surface == placement.surface,
        let otherItem = DecorItem.item(shopID: other.item),
        let otherSpan = Self.span(of: other, item: otherItem)
      else { return nil }
      if placement.surface == .floor, item.isFlat || otherItem.isFlat { return nil }
      return span.overlaps(otherSpan) ? other.item : nil
    }
  }

  /// Puts a piece on `placement`: where it fits it stands; on one other piece it swaps with it when both fit
  /// in each other's place, else moves it aside to the nearest spot that fits, else is rejected.
  public func dropping(_ placement: Placement, in room: DecorRoom = .home) -> Drop {
    let verdict = verdict(placement, in: room)
    if verdict == .fits { return .fits(putting(placement)) }
    let blocking = blockers(of: placement)
    guard verdict == .occupied, blocking.count == 1, let other = self.placement(of: blocking[0]),
      let mine = self.placement(of: placement.item)
    else { return .rejected(verdict) }

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
    return .rejected(verdict)
  }

  /// The room as a pair that never arranged it has it: the room's own furniture at home, nothing the player
  /// bought stood until it is settled again.
  public func reset(owned: Set<String>, in room: DecorRoom = .home) -> DecorLayout {
    DecorLayout().settled(owned: owned, in: room)
  }
}
