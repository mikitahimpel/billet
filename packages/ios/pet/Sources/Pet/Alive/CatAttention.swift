import BilletKit
import Foundation

/// Something that can take the cat's attention: where it is from her, how much it matters and for
/// how long at most she watches it.
public struct CatStimulus: Hashable, Sendable {
  public enum Source: Hashable, Sendable {
    /// Whoever watches her: the camera.
    case viewer
    case touch
    /// The partner coming in, from the side of the room away from the viewer.
    case partner
    /// Where she is about to go.
    case destination
    /// Something that stands in the room, by its name there.
    case place(String)
    /// A noise in the room that she is made to hear.
    case noise
    /// A noise only she hears.
    case sound
    /// Nothing in particular: a look about.
    case nothing
  }

  /// How it reaches her. A sound turns an ear before the head; a sight, or a look of her own
  /// choosing, turns the head at once.
  public enum Sense: Hashable, Sendable {
    case heard, seen, own
  }

  public var source: Source
  public var sense: Sense
  /// Radians from straight ahead of her body, in the sense her head turns; it may be behind her.
  public var bearing: Double
  /// Radians above level.
  public var elevation: Double
  /// From 0, not worth an ear, to 1, a start.
  public var salience: Double
  /// Seconds she watches it before she lets go, if nothing takes her off it sooner.
  public var hold: Double

  public init(
    _ source: Source, _ sense: Sense, bearing: Double, elevation: Double = 0, salience: Double,
    hold: Double
  ) {
    self.source = source
    self.sense = sense
    self.bearing = bearing
    self.elevation = elevation
    self.salience = salience
    self.hold = hold
  }
}

/// The cat's attention, one thing at a time, as an animal orients: the ears go to a sound first,
/// the head follows only when it is worth turning for, she watches it stock still, and lets go of
/// it with a blink. Time is an event, so a test steps it without waiting.
public enum CatAttention: Machine {
  public enum State: Equatable, Sendable {
    /// Nothing holds her.
    case free
    /// Her ears are on it and she has gone still; `turns` says whether her head follows.
    case pricked(CatStimulus, since: Double, turns: Bool)
    /// Her head is on it, or on its way.
    case watching(CatStimulus, since: Double)
    /// She has let go and is not yet ready to look at anything of her own choosing.
    case releasing(CatStimulus, since: Double)
  }

  public enum Event: Sendable {
    case noticed(CatStimulus, at: Double)
    /// What she attends to is somewhere else now, as a finger moves.
    case moved(CatStimulus.Source, bearing: Double, elevation: Double)
    case gone(CatStimulus.Source, at: Double)
    case time(Double)
  }

  public enum Output: Equatable, Sendable {
    /// Her head starts round to it.
    case turned(CatStimulus)
    /// She lets go of it, with a blink.
    case released(CatStimulus)
  }

  /// Below this an ear does not even turn.
  public static let earThreshold = 0.15
  /// From this on the head turns to it as well.
  public static let headThreshold = 0.4
  /// How much more than her interest in what she watches a new thing must matter to take her off it.
  public static let takeover = 1.25
  /// Seconds an ear stays on a thing the head does not turn for.
  public static let earDwell = 0.9
  /// Seconds after letting go before she is free.
  public static let letGo = 0.7

  /// Seconds the ears are on a sound before the head starts round: shorter the more it matters,
  /// and long enough to be seen as two moves.
  public static func earLead(_ stimulus: CatStimulus) -> Double {
    stimulus.sense == .heard ? 0.5 - 0.25 * min(max(stimulus.salience, 0), 1) : 0
  }

  /// What is left of her interest in `stimulus` after watching it for `elapsed` seconds: half is
  /// gone by the end of its hold.
  public static func interest(_ stimulus: CatStimulus, elapsed: Double) -> Double {
    stimulus.salience * (1 - 0.5 * min(max(elapsed / max(stimulus.hold, 0.01), 0), 1))
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.free, .noticed(let new, let now)), (.releasing, .noticed(let new, let now)):
      guard new.salience >= earThreshold else { return (state, []) }
      return (.pricked(new, since: now, turns: new.salience >= headThreshold), [])

    case (.pricked(let old, _, _), .noticed(let new, let now)):
      if new.source == old.source || new.salience > old.salience {
        return (.pricked(new, since: now, turns: new.salience >= headThreshold), [])
      }
      return (state, [])

    case (.watching(let old, let since), .noticed(let new, let now)):
      if new.source == old.source {
        var kept = new
        kept.salience = max(new.salience, interest(old, elapsed: now - since))
        return (.watching(kept, since: since), [])
      }
      guard new.salience >= headThreshold,
        new.salience >= takeover * interest(old, elapsed: now - since)
      else { return (state, []) }
      return (.pricked(new, since: now, turns: true), [])

    case (.pricked(let stimulus, let since, let turns), .time(let now)):
      if turns, now - since >= earLead(stimulus) {
        return (.watching(stimulus, since: now), [.turned(stimulus)])
      }
      if !turns, now - since >= earDwell { return (.free, []) }
      return (state, [])

    case (.watching(let stimulus, let since), .time(let now)):
      guard now - since >= stimulus.hold else { return (state, []) }
      return (.releasing(stimulus, since: now), [.released(stimulus)])

    case (.releasing(_, let since), .time(let now)):
      return (now - since >= letGo ? .free : state, [])

    case (
      .pricked(var stimulus, let since, let turns), .moved(let source, let bearing, let elevation)
    ):
      guard source == stimulus.source else { return (state, []) }
      stimulus.bearing = bearing
      stimulus.elevation = elevation
      return (.pricked(stimulus, since: since, turns: turns), [])

    case (.watching(var stimulus, let since), .moved(let source, let bearing, let elevation)):
      guard source == stimulus.source else { return (state, []) }
      stimulus.bearing = bearing
      stimulus.elevation = elevation
      return (.watching(stimulus, since: since), [])

    case (.pricked(let stimulus, _, _), .gone(let source, _)):
      return (source == stimulus.source ? .free : state, [])

    case (.watching(let stimulus, _), .gone(let source, let now)):
      guard source == stimulus.source else { return (state, []) }
      return (.releasing(stimulus, since: now), [.released(stimulus)])

    // Nothing to follow, lose or wait for.
    case (.free, .moved), (.free, .gone), (.free, .time), (.releasing, .moved), (.releasing, .gone):
      return (state, [])
    }
  }
}
