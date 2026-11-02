import Foundation

/// What the first-launch scene shows: a soft heart floating over a windowsill of candles.
public struct OnboardingSceneState: Equatable, Sendable {
  public enum Moment: Equatable, Sendable {
    /// The camera glides in out of the dark while the candles and lights come on one by one.
    case arriving
    /// At rest: the heart beats and floats over the candles. A scene that opens here skips the
    /// flight; one that was arriving finishes it quickly.
    case resting
  }

  public var moment: Moment

  public init(moment: Moment) {
    self.moment = moment
  }
}

/// What the first-launch scene reports to its host.
public enum OnboardingSceneEvent: Hashable, Sendable {
  /// The camera reached its place, at the end of the flight or soon after it was cut short.
  case arrived
  /// The heart was tapped, and squished.
  case heartTapped
}
