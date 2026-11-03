/// What a touch in the room landed on, as a room finds it from the touch's first point.
public enum CatTouchTarget: Hashable, Sendable {
  case cat
  case toy(CatToy)
  case bowl
  /// The jar a treat is taken from.
  case treats
  /// Open floor the cat can walk on.
  case floor
  /// Anything else a room reacts to itself: the lamp, the note, furniture.
  case scenery
  /// Sky, walls, or nothing at all.
  case nothing
}

/// The kind of touch, once it is known.
public enum CatTouchGesture: Hashable, Sendable {
  case tap
  case doubleTap
  case drag
  case longPress
}

/// Where a touch goes. Touches on the cat and its things are the cat's; everything else keeps
/// the camera's own gestures, so an empty-space drag still turns the room.
public enum CatTouchRoute: Hashable, Sendable {
  /// A tap on the cat: its ears perk.
  case pat
  case stroke
  case trick
  case lift
  /// The finger carries the toy: the wand's feather or the laser's dot.
  case carry(CatToy)
  /// The toy rolls off with the speed the finger lets go at.
  case fling(CatToy)
  case fillBowl
  /// A treat follows the finger until the cat takes it.
  case offerTreat
  case call
  /// The room's own handling: the lamp, the note, a wobble.
  case scenery
  /// The camera's gesture: turning the room, or going back home on a double tap.
  case camera
  case ignore
}

public enum CatTouchRouter {
  /// Where `gesture` on `target` goes. While the cat is held up, only the hold moves it.
  public static func route(
    _ gesture: CatTouchGesture, on target: CatTouchTarget, isHoldingCat: Bool = false
  ) -> CatTouchRoute {
    if isHoldingCat { return .ignore }
    switch (gesture, target) {
    case (.tap, .cat): return .pat
    case (.tap, .bowl): return .fillBowl
    case (.tap, .toy(let toy)): return toy.isThrown ? .fling(toy) : .ignore
    case (.tap, .scenery): return .scenery
    case (.tap, .treats), (.tap, .floor), (.tap, .nothing): return .ignore

    case (.doubleTap, .cat): return .trick
    case (.doubleTap, .floor): return .call
    case (.doubleTap, .toy), (.doubleTap, .bowl), (.doubleTap, .treats),
      (.doubleTap, .scenery), (.doubleTap, .nothing):
      return .camera

    case (.drag, .cat): return .stroke
    case (.drag, .toy(let toy)): return toy.isThrown ? .fling(toy) : .carry(toy)
    case (.drag, .treats): return .offerTreat
    case (.drag, .bowl), (.drag, .floor), (.drag, .scenery), (.drag, .nothing): return .camera

    case (.longPress, .cat): return .lift
    case (.longPress, .toy), (.longPress, .bowl), (.longPress, .treats), (.longPress, .floor),
      (.longPress, .scenery), (.longPress, .nothing):
      return .ignore
    }
  }
}
