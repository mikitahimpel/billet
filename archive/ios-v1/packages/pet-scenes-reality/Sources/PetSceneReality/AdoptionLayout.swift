import Foundation
import PetScene
import simd

/// Where everything stands when the pair chooses its cat, in room units (``GenzRoomPoint``): a
/// cosy corner at night with a rug, five cushions in two staggered rows under a window, candles
/// on the floor and fairy lights along the wall. The cats are numbered left to right.
enum AdoptionLayout {
  static let width: Float = 7
  static let height: Float = 9
  static let wall: Float = 0.3

  /// The cushions' middles on the floor, left to right: back, front, back, front, back.
  static let cushions: [GenzRoomPoint] = [
    GenzRoomPoint(1.2, 2.2, 0), GenzRoomPoint(2.35, 4.15, 0), GenzRoomPoint(3.5, 2.2, 0),
    GenzRoomPoint(4.65, 4.15, 0), GenzRoomPoint(5.8, 2.2, 0),
  ]
  static let cushion = (width: Float(1.4), depth: Float(1.2), height: Float(0.3))
  static let catLength: Float = 1.3
  /// How far a cat comes forward off its cushion when it is a candidate, at most.
  static let stepForward: Float = 1.1
  /// How high a cat's head is over the floor, where the marks float.
  static let headHeight: Float = 1.25
  /// The middle of a cat's body over the floor, where the rings go round.
  static let bodyHeight: Float = 0.7

  static let window = (x0: Float(2.1), x1: Float(4.9), z0: Float(3.6), z1: Float(6.9))
  static let rug = (x0: Float(0.4), x1: Float(6.6), y0: Float(1.2), y1: Float(6.2))
  static let candles: [GenzRoomPoint] = [
    GenzRoomPoint(0.55, 5.6, 0), GenzRoomPoint(0.95, 6.1, 0), GenzRoomPoint(6.4, 5.8, 0),
  ]
  /// Fairy lights in a sag along the wall, over the window.
  static let beads: [GenzRoomPoint] = (0..<17).map { index in
    let t = Float(index) / 16
    let sag = 0.5 * sin(t * .pi)
    return GenzRoomPoint(0.4 + t * 6.2, 0.22, 7.6 - sag)
  }

  /// Where the adopted cat walks out: off the rug to the right, towards the viewer.
  static let exit = GenzRoomPoint(8.4, 7.4, 0)

  static let camera = GenzCamera.Home(
    target: GenzRoomPoint(3.5, 3.2, 1.6).scene, yaw: 0, pitch: 0.4, distance: 21,
    fieldOfView: 40, yawLimits: -0.15...0.15, pitchLimits: 0.28...0.55)

  /// Where cat `index` stands when it is `forward` of the way off its cushion, and on what.
  static func spot(_ index: Int, forward: Float) -> GenzRoomPoint {
    let base = cushions[index % cushions.count]
    let towardsMiddle = (3.5 - base.x) * 0.12 * forward
    let onCushion = forward < 0.3
    return GenzRoomPoint(
      base.x + towardsMiddle, base.y + stepForward * forward, onCushion ? cushion.height : 0)
  }

  /// The way cat `index` faces: towards the viewer, turned a little to the middle.
  static func heading(_ index: Int) -> Float {
    (3.5 - cushions[index % cushions.count].x) * 0.1
  }

  /// How far forward each of `count` cats wants to be in `state`, from 0 to 1. The cat both picked
  /// comes half way, the two candidates of a bid all the way, and a cat only one partner picked
  /// a little. Once adopted, only the adopted cat stays forward.
  static func forward(_ state: AdoptionSceneState) -> [Float] {
    (0..<state.cats.count).map { index in
      switch state.moment {
      case .adopted, .leaving:
        return index == state.adopted ? 1 : 0
      case .choosing:
        let mine = state.mine == index
        let theirs = state.theirs == index
        if mine && theirs { return 0.55 }
        if mine || theirs, state.mine != nil, state.theirs != nil { return 1 }
        return mine || theirs ? 0.25 : 0
      }
    }
  }

  /// What each cat does in `state`.
  enum Act: Equatable {
    /// Sits on its cushion, fidgeting now and then.
    case sit
    /// One of two candidates while the picks differ: `playful` crouches and pounces, the other
    /// headbutts the air. A small, cute bid with no timer.
    case bid(playful: Bool)
    /// The cat both picked: it perks up and looks at the viewer.
    case agreed
    /// Just adopted: it greets the pair.
    case greet
    /// Another cat once one is adopted: it curls up.
    case settle
    /// The adopted cat, walking out.
    case walk
  }

  static func acts(_ state: AdoptionSceneState) -> [Act] {
    (0..<state.cats.count).map { index in
      switch state.moment {
      case .adopted: return index == state.adopted ? .greet : .settle
      case .leaving: return index == state.adopted ? .walk : .settle
      case .choosing:
        if state.agreed == index { return .agreed }
        if let mine = state.mine, let theirs = state.theirs, mine != theirs {
          if index == mine { return .bid(playful: mine < theirs) }
          if index == theirs { return .bid(playful: theirs < mine) }
        }
        return .sit
      }
    }
  }
}

/// The adopted cat walking out, and the camera going after it, over `length` seconds.
enum AdoptionExit {
  static let length: TimeInterval = 3.4
  /// The last stretch, over which the scene goes dark into the room.
  static let fade: TimeInterval = 0.8
  /// With reduced motion the cat stays and the scene only fades.
  static let reducedLength: TimeInterval = 0.9

  /// How far along the way out the cat is at `time`, from 0 to 1.
  static func progress(at time: TimeInterval) -> Float {
    Float(TimelineEase.smoother(min(max(time / length, 0), 1)))
  }

  /// Where the cat walking out of `index`'s place is at `time`.
  static func spot(from index: Int, at time: TimeInterval) -> GenzRoomPoint {
    let start = AdoptionLayout.spot(index, forward: 1)
    let end = AdoptionLayout.exit
    let t = progress(at: time)
    return GenzRoomPoint(
      start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t, 0)
  }

  /// Which way the walking cat faces: towards the way out.
  static func heading(from index: Int) -> Float {
    let start = AdoptionLayout.spot(index, forward: 1)
    let end = AdoptionLayout.exit
    return atan2(end.x - start.x, end.y - start.y)
  }

  /// The camera's turn, lift and distance multiple at `time`, swinging round after the cat.
  static func flight(at time: TimeInterval) -> SIMD3<Float> {
    let t = progress(at: time)
    return [0.42 * t, -0.16 * t, 1 - 0.38 * t]
  }

  /// How dark the scene is at `time`: dark at the end, into the room.
  static func darkness(at time: TimeInterval, reduceMotion: Bool) -> Double {
    let total = reduceMotion ? reducedLength : length
    let fade = reduceMotion ? reducedLength : self.fade
    return min(max((time - (total - fade)) / fade, 0), 1)
  }

  static func isDone(at time: TimeInterval, reduceMotion: Bool) -> Bool {
    time >= (reduceMotion ? reducedLength : length)
  }
}
