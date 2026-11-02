import Foundation

/// The opening of each styled room as functions of seconds since it started, shared by the 3D
/// room and its flat layers so they stay in step. Every value runs from 0 to 1.
///
/// Sunset Lamp: the room opens dark, the LED strip stutters on, the lamp clicks, the disc blooms
/// across the wall and the note is taped into its middle. Window Seat: the street lamp outside
/// stutters on, its light comes through the note, then the LED around the frame warms up.
enum GenzOpening {
  /// Long enough for every value to have reached its end.
  static let length: Double = 3

  // MARK: Sunset Lamp

  /// The dark over the room, from 0.82 down to nothing once the lamp is on.
  static func sunsetDim(_ time: Double) -> Double {
    0.82 * (1 - eased(time, from: 0.35, length: 1.1))
  }

  /// The LED strip, in three steps.
  static func sunsetLED(_ time: Double) -> Double {
    stepped(time, from: 0.1, length: 0.5, steps: 3)
  }

  /// The lamp's lens and light: off, then on with a click.
  static func lampClick(_ time: Double) -> Double {
    stepped(time, from: 0.35, length: 0.3, steps: 2)
  }

  /// How far the disc has bloomed. Its size runs from 0.35 to 1 with it.
  static func discBloom(_ time: Double) -> Double {
    eased(time, from: 0.45, length: 1.2)
  }

  /// The disc's slow breathing once it has bloomed, between 0.86 and 1.
  static func discBreath(_ time: Double) -> Double {
    guard time > 2 else { return 1 }
    let phase = (time - 2).truncatingRemainder(dividingBy: 14) / 7
    let swing = phase <= 1 ? phase : 2 - phase
    return 1 - 0.14 * (0.5 - 0.5 * cos(swing * .pi))
  }

  /// The note being taped up: how much of it shows, and its turn from -4° to straight.
  static func sunsetNote(_ time: Double) -> Double {
    eased(time, from: 1.05, length: 0.7)
  }

  // MARK: Window Seat

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

  /// A headlight sliding across the room, from 0 to 1 while it passes and `nil` between cars.
  /// Cars come every 12 to 40 seconds, the same each night for a given `seed`.
  static func headlight(_ time: Double, seed: UInt64 = 7) -> Double? {
    var start = 3.0
    var state = seed
    while start <= time {
      let pass = 2.6
      if time < start + pass { return (time - start) / pass }
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      start += pass + 12 + Double(state >> 40) / Double(1 << 24) * 28
    }
    return nil
  }

  /// How warm a room is after a note lands, from 1 just after down to 0 over a few seconds.
  static func warmth(sinceLanding time: Double?) -> Double {
    guard let time, time >= 0 else { return 0 }
    return max(0, 1 - time / 6)
  }

  // MARK: Curves

  /// An ease-out from `from` over `length` seconds.
  static func eased(_ time: Double, from start: Double, length: Double) -> Double {
    let progress = min(max((time - start) / length, 0), 1)
    return 1 - pow(1 - progress, 3)
  }

  static func stepped(_ time: Double, from start: Double, length: Double, steps: Int) -> Double {
    let progress = min(max((time - start) / length, 0), 1)
    return (progress * Double(steps)).rounded(.down) / Double(steps)
  }
}
