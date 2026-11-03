import Foundation
import RealityKit

/// How fast the cat's walk and run clips move its feet. Clips stay in place: travel comes from the
/// room, at these speeds so that planted paws stay still.
enum NookiClip {
  /// How fast a planted paw moves back in the walk clip at normal rate, in the model's metres a
  /// second. Every made cat walks one 0.083 m stride a second with each paw down for 62% of it, so
  /// a planted paw covers the stride in 0.62 s; measured off the hero and the detailed cat it is
  /// 0.125 to 0.128. Travel at this speed keeps paws still on the floor.
  static let pawSpeed: Float = 0.126

  /// The cat's scale in a room that `walkingSpeed` and `runningSpeed` are given for.
  static let referenceScale: Float = 1.25

  /// How fast the walk clip's feet travel at normal rate, in metres a second in the room.
  static let walkingSpeed: Float = pawSpeed * referenceScale

  /// How fast a planted paw moves back in the run clip at normal rate, in the model's metres a
  /// second: a gallop of 0.45 s with each paw down for 36% of it and travelling 0.08 m, which is
  /// 0.49 by design; measured off the four detailed cats it is 0.42 to 0.47.
  static let runPawSpeed: Float = 0.46

  /// How fast the run clip's feet travel at normal rate, in metres a second in the room: about
  /// 3.7 times the walk. A slower run plays the clip slower.
  static let runningSpeed: Float = runPawSpeed * referenceScale

  private static let fastestWalk: Float = 3

  /// The playback rate that keeps feet from sliding at `speed` metres a second.
  static func walkRate(forTravelAt speed: Float) -> Float {
    min(max(speed / walkingSpeed, 1), fastestWalk)
  }
}
