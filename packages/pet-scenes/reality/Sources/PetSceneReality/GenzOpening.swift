import Foundation

/// The room's opening as functions of seconds since it started, shared by the 3D room and its
/// flat layers so they stay in step. Every value runs from 0 to 1: the street lamp outside
/// stutters on, its light comes through the note, then the LED around the frame warms up.
enum GenzOpening {
  /// Long enough for every value to have reached its end.
  static let length: Double = 3

  /// The dark over the room, from 0.75 to nothing.
  static func windowDim(_ time: Double) -> Double {
    0.75 * (1 - eased(time, from: 0.2, length: 1.6))
  }

  /// The street lamp stuttering on.
  static func streetLamp(_ time: Double) -> Double {
    let local = (time - 0.3) / 1.1
    guard local >= 0 else { return 0 }
    switch local {
    case ..<0.12: return 0
    case ..<0.2: return 1
    case ..<0.34: return 0.1
    case ..<0.42: return 1
    case ..<0.5: return 0.3
    default: return 1
    }
  }

  /// The street light coming through the note's paper.
  static func backlight(_ time: Double) -> Double {
    eased(time, from: 1.2, length: 0.9)
  }

  /// The drawing appearing on the glass, from dim to lit.
  static func windowNote(_ time: Double) -> Double {
    eased(time, from: 1.1, length: 0.9)
  }

  /// The LED around the window frame warming up.
  static func windowLED(_ time: Double) -> Double {
    eased(time, from: 1.6, length: 1.2)
  }

  // MARK: Afterwards

  /// How warm a room is after a note lands, from 1 just after down to 0 over a few seconds.
  static func warmth(sinceLanding time: Double?) -> Double {
    guard let time, time >= 0 else { return 0 }
    return max(0, 1 - time / warmthLength)
  }

  /// How long a room stays warm after a note lands, in seconds.
  static let warmthLength: Double = 6

  // MARK: Curves

  /// An ease-out from `from` over `length` seconds.
  static func eased(_ time: Double, from start: Double, length: Double) -> Double {
    let progress = min(max((time - start) / length, 0), 1)
    return 1 - pow(1 - progress, 3)
  }

}
