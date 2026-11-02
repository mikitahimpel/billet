import Foundation
import Pet
import PetScene
import RealityKit
import simd

/// The opening a room plays when the host asks it to fly in, as numbers against the room's clock.
/// Both kinds of room keep one, and read the camera, the light and the cat's cues from it.
struct SceneFlight: Equatable {
  /// The room clock when the flight began.
  private(set) var start: Double
  private(set) var id: Int
  private var cuesSent = Set<CatCue>()

  /// Starts a flight at `clock`, already over when `atEnd`.
  init(id: Int, clock: Double, atEnd: Bool) {
    self.id = id
    start = atEnd ? clock - FlyInTimeline.length : clock
    if atEnd { cuesSent = Set(CatCue.allCases) }
  }

  func time(at clock: Double) -> Double { clock - start }

  func isOver(at clock: Double) -> Bool { time(at: clock) >= FlyInTimeline.length }

  /// Jumps to the end, as a skip does. The cues not yet sent are dropped.
  mutating func skip(at clock: Double) {
    start = min(start, clock - FlyInTimeline.length)
    cuesSent = Set(CatCue.allCases)
  }

  /// The cat's cues whose moment has come by `clock` and that have not been sent, in order.
  mutating func dueCues(at clock: Double) -> [CatCue] {
    let time = time(at: clock)
    var due: [CatCue] = []
    for (cue, moment) in [(CatCue.wakeUp, FlyInTimeline.wake), (.lookAtCamera, FlyInTimeline.look)]
    where time >= moment && !cuesSent.contains(cue) {
      cuesSent.insert(cue)
      due.append(cue)
    }
    return due
  }
}

/// How a room is lit for an hour of the day: the sun through the window, the ambient level and
/// the colour of the sky seen outside.
struct RoomDayLook: Equatable {
  /// The directional light's strength, in lux.
  var sunIntensity: Float
  var sunColour: SIMD3<Float>
  /// Added to the ambient light's exponent: below zero darkens, above brightens.
  var ambientShift: Float
  var lampOn: Bool

  init(_ light: DayLight) {
    let sun = Float(light.sun)
    let warmth = Float(light.warmth)
    sunIntensity = light.phase == .night ? 120 : 400 + 2600 * sun
    let white: SIMD3<Float> = [1, 0.97, 0.92]
    let orange: SIMD3<Float> = [1, 0.62, 0.32]
    let moon: SIMD3<Float> = [0.55, 0.65, 1]
    sunColour = light.phase == .night ? moon : simd_mix(white, orange, .init(repeating: warmth))
    ambientShift = light.phase == .night ? -0.9 : -0.4 + 0.9 * sun
    lampOn = light.lampOn
  }

  /// The sky seen through a window at the hour of `light`, and how strongly it glows.
  static func sky(_ light: DayLight) -> (colour: SIMD3<Float>, glow: Float) {
    switch light.phase {
    case .morning: ([1, 0.8, 0.55], 0.7)
    case .day: ([0.45, 0.7, 1], 0.9)
    case .goldenHour: ([1, 0.45, 0.2], 0.8)
    case .night: ([0.12, 0.16, 0.4], 0.25)
    }
  }
}

extension NookiMotion {
  /// How long the cat stays up when woken by a cue.
  static let wakeLength = 3.6

  /// The cat getting up from sleep for a while, with no hop: the clips do the stretching.
  static func wake(_ elapsed: Double, reduceMotion: Bool) -> NookiFrame {
    guard (0..<wakeLength).contains(elapsed) else { return NookiFrame() }
    let eyesOpen = elapsed < wakeLength - 0.3
    if reduceMotion { return NookiFrame(eyesOpen: eyesOpen) }
    let rise = min(elapsed / 0.5, (wakeLength - elapsed) / 0.6)
    return NookiFrame(wake: Float(min(max(rise, 0), 1)), eyesOpen: eyesOpen)
  }
}

extension SIMD3<Float> {
  /// The colour these red, green and blue parts make, for a light or a material.
  var platformColour: RealityKit.Material.Color {
    RealityKit.Material.Color(red: CGFloat(x), green: CGFloat(y), blue: CGFloat(z), alpha: 1)
  }
}
