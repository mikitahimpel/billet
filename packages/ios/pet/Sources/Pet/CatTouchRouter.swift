import Foundation
#if canImport(simd)
  import simd
#endif

/// What a touch in the room landed on, as a room finds it from the touch's first point.
public enum CatTouchTarget: Hashable, Sendable {
  case cat
  case toy(CatToy)
  case bowl
  /// The jar a treat is taken from.
  case treats
  case floor
  /// Anything else a room reacts to itself: the lamp, the note, furniture.
  case scenery
  /// Sky, walls, or nothing at all.
  case nothing
}

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

  /// How long a finger rests on the cat or a toy before moving for the drag to be theirs.
  public static let restBeforeTaking: TimeInterval = 0.15
  /// How far a quick drag goes before its direction is read, in points.
  public static let readingDistance: Double = 12

  /// The cat, a toy or the treat jar under the finger takes the drag when the finger rested on it
  /// first, or when it sets off along what that thing does (a stroke along the body, any toy move);
  /// a quick mostly sideways swipe turns the room. Nil until a quick drag has gone far enough.
  public static func routeDrag(
    on target: CatTouchTarget, start: CatDragStart, isHoldingCat: Bool = false
  ) -> CatTouchRoute? {
    let route = route(.drag, on: target, isHoldingCat: isHoldingCat)
    switch route {
    case .stroke, .carry, .fling, .offerTreat: break
    default: return route
    }
    if start.rested >= restBeforeTaking { return route }
    let move = start.movement
    guard simd_length(move) >= readingDistance else { return nil }
    if abs(move.x) > abs(move.y) * 1.5 { return .camera }
    switch target {
    case .cat:
      guard let axis = start.axis, simd_length(axis) > 0.001 else { return route }
      let along = abs(simd_dot(simd_normalize(move), simd_normalize(axis)))
      return along >= 0.8 ? route : .camera
    default:
      return route
    }
  }
}

public struct CatDragStart: Hashable, Sendable {
  /// How long the finger rested before it began to move, in seconds.
  public var rested: TimeInterval
  /// How far the finger has gone since it touched down, in points with y down.
  public var movement: SIMD2<Double>
  /// The line a stroke runs along on screen, head to tail, when the drag began on the cat.
  public var axis: SIMD2<Double>?

  public init(rested: TimeInterval, movement: SIMD2<Double>, axis: SIMD2<Double>? = nil) {
    self.rested = rested
    self.movement = movement
    self.axis = axis
  }
}
