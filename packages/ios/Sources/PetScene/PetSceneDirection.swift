import CoreGraphics
import Foundation
import Pet
import SwiftUI

/// A camera flight into the room, asked for by the host. A new `id` starts one; the same `id`
/// with `isSkipped` jumps to where it ends.
public struct PetSceneFlyIn: Hashable, Sendable {
  public var id: Int
  public var isSkipped: Bool

  public init(id: Int, isSkipped: Bool = false) {
    self.id = id
    self.isSkipped = isSkipped
  }
}

/// When each part of the opening happens, in seconds from its start, and where the camera is on
/// the way. Scenes and hosts read the same numbers, so they stay in step. It is short, a glide of
/// under two seconds, because it plays on every cold launch.
public enum FlyInTimeline {
  /// The camera's glide from a little way out to its usual place.
  public static let flight = 0.0...1.8
  /// The room's lights going from dark to full.
  public static let lightsUp = 0.0...0.9
  /// When the cat is asked to look up at the camera, to greet whoever opened the app.
  public static let look = 1.0
  /// The latest note growing in, once the cat has looked up.
  public static let noteReveal = 1.3...1.8
  /// When the whole opening is over.
  public static let length = 1.9

  /// How the camera stands off its usual place at `time`: extra turn and lift in radians, and
  /// distance as a multiple of the usual one. All return to zero, zero and one by the flight's end.
  public static func offset(at time: Double) -> (yaw: Float, pitch: Float, distance: Float) {
    let left = Float(1 - eased(progress(time, in: flight)))
    return (yaw: 0.3 * left, pitch: 0.12 * left, distance: 1 + 0.8 * left)
  }

  /// From 0 to 1, how far the lights have come up at `time`.
  public static func lights(at time: Double) -> Double {
    eased(progress(time, in: lightsUp))
  }

  /// From 0 to 1, how far the note has grown in at `time`.
  public static func note(at time: Double) -> Double {
    eased(progress(time, in: noteReveal))
  }

  static func progress(_ time: Double, in span: ClosedRange<Double>) -> Double {
    min(max((time - span.lowerBound) / (span.upperBound - span.lowerBound), 0), 1)
  }

  /// Slow at both ends, with no jump in speed at either.
  static func eased(_ value: Double) -> Double {
    value * value * value * (value * (value * 6 - 15) + 10)
  }
}

/// The light a room should take from the clock: the hour here, and the partner's hour for the sky
/// seen from the room, when their time zone is known.
public struct PetSceneDayLight: Hashable, Sendable {
  public var here: DayLight
  public var theirs: DayLight?

  public init(here: DayLight, theirs: DayLight?) {
    self.here = here
    self.theirs = theirs
  }
}

extension EnvironmentValues {
  /// Asks the scene to fly its camera in and play its opening. `nil` leaves the camera alone.
  @Entry public var petSceneFlyIn: PetSceneFlyIn? = nil
  /// Where a finger rests on the scene, in the scene's points, for the cat to look at. `nil` when
  /// nothing touches it.
  @Entry public var petSceneGaze: CGPoint? = nil
  /// False when a drag on the scene is for the cat to watch rather than to turn the room.
  @Entry public var petSceneOrbits = true
  /// Whether the camera leans with the phone. Scenes that always lean ignore it.
  @Entry public var petSceneFollowsTilt = false
  /// False when the host lays the scene's controls out itself, so the scene draws none of its own
  /// until the host opens them.
  @Entry public var petSceneShowsControls = true
  /// True when the room should fill the view edge to edge rather than fit inside it.
  @Entry public var petSceneFillsView = false
  /// Lights the room for the time of day. `nil` keeps the room's own lighting.
  @Entry public var petSceneDayLight: PetSceneDayLight? = nil
  /// How the room is lit: its lamp, glow, haze, shadows and grading. A host that sets nothing
  /// gets the room as it was made.
  @Entry public var petSceneLighting = RoomLighting.off
  /// Which furniture fills the styled rooms. A host that sets nothing gets the first pieces.
  @Entry public var petSceneFurniture = RoomFurniture.original
  /// Which room the scene shows the cat in. A host that sets nothing gets Window Seat.
  @Entry public var petSceneRoom = HomeRoom.standard
  /// Whether the styled rooms show the generated (Idol) props in place of their hand-made ones.
  @Entry public var petSceneIdolProps = false
  /// Called when the opening asked for by ``petSceneFlyIn`` starts, which is once the room is
  /// built and on screen: a host covering the room while it loads can uncover it then.
  @Entry public var petSceneOpeningStarted: (@MainActor () -> Void)? = nil
  /// Called when the opening asked for by ``petSceneFlyIn`` is over, played out or skipped.
  @Entry public var petSceneOpeningEnded: (@MainActor () -> Void)? = nil
  /// The newest cue for the cat, from ``CatDirector``.
  @Entry public var petSceneCatCue: CatCueRequest? = nil
}
