import Foundation

/// Which half of the heart is this phone's, as the viewer sees it. The partner's phone shows the
/// mirror: the other half is theirs.
public enum HeartSide: String, Hashable, Sendable {
  case left
  case right

  public var other: HeartSide {
    switch self {
    case .left: .right
    case .right: .left
    }
  }
}

/// What the first-launch scene shows: a soft heart floating over a windowsill of candles, which
/// opens into two halves while the pair is made and joins again once it is.
public struct OnboardingSceneState: Equatable, Sendable {
  public enum Moment: Equatable, Sendable {
    /// The camera glides in out of the dark while the candles and lights come on one by one.
    case arriving
    /// At rest: the heart beats and floats over the candles. A scene that opens here skips the
    /// flight; one that was arriving finishes it quickly.
    case resting
    /// The heart has opened: this phone's half stays, and the partner's is `partner`.
    case apart(partner: PartnerHalf)
    /// The partner's half flies in and the two join, with a burst of warm light.
    case together
  }

  /// Where the partner's half is while the heart is apart.
  public enum PartnerHalf: Equatable, Sendable {
    /// Floating on its side, glowing softly and pulsing: waiting for the partner.
    case waiting
    /// Gone from the scene, until it flies in.
    case away
  }

  public var moment: Moment
  /// This phone's half.
  public var mine: HeartSide
  /// The pair's code, shown on a little paper tag on the sill, or `nil` for no tag.
  public var code: String?

  public init(moment: Moment, mine: HeartSide = .left, code: String? = nil) {
    self.moment = moment
    self.mine = mine
    self.code = code
  }
}

public enum OnboardingSceneEvent: Hashable, Sendable {
  /// The camera reached its place, at the end of the flight or soon after it was cut short.
  case arrived
  /// The heart, or this phone's half, was tapped, and squished.
  case heartTapped
  /// The halves met: the moment for a burst of haptics.
  case joined
  case codeTapped
}
