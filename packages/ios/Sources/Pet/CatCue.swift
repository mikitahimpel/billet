import Observation

/// A moment of the cat's that something other than the scene decides on, such as an opening or an
/// idle scheduler. The scene plays it with the cat's own clips.
public enum CatCue: String, CaseIterable, Hashable, Sendable {
  /// Opens its eyes and gets up from sleep for a few seconds.
  case wakeUp
  /// Turns to face the camera, as if looking at whoever holds the phone.
  case lookAtCamera
}

/// One cue as sent, numbered so that the same cue twice in a row still reads as new.
public struct CatCueRequest: Hashable, Sendable {
  public let cue: CatCue
  public let serial: Int

  public init(cue: CatCue, serial: Int) {
    self.cue = cue
    self.serial = serial
  }
}

/// Where cues for the cat are sent. The host owns one, hands ``latest`` to the scene, and anything
/// that schedules the cat's moments sends through it.
@MainActor
@Observable
public final class CatDirector {
  public private(set) var latest: CatCueRequest?

  public init() {}

  public func send(_ cue: CatCue) {
    latest = CatCueRequest(cue: cue, serial: (latest?.serial ?? 0) + 1)
  }
}
