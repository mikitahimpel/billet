import BilletKit

/// Keeps this phone up to date with the partner while the app is in front and paired: the room's
/// socket is followed, and everything the socket can miss is pulled at once and then on a clock.
/// The socket can be down, backing off or silently dead, so the clock is the backstop, not the
/// path. Every tick and pull carries a number from `serial`; one that is not current is stale and
/// changes nothing.
nonisolated public enum PartnerSyncMachine: Machine {
  public struct State: Equatable, Sendable {
    public var mode: Mode
    public var serial: Int

    public init(mode: Mode, serial: Int) {
      self.mode = mode
      self.serial = serial
    }

    /// Unpaired, the app not yet in front.
    public static let initial = State(mode: .away(paired: false), serial: 0)
  }

  public enum Mode: Equatable, Sendable {
    /// The app is not in front; `paired` is whether it follows the partner on its return.
    case away(paired: Bool)
    /// In front without a partner: nothing to follow.
    case unpaired
    case following(Following)
  }

  public struct Following: Equatable, Sendable {
    /// The tick this clock waits for.
    public var clock: Int
    public var pull: Pull

    public init(clock: Int, pull: Pull) {
      self.clock = clock
      self.pull = pull
    }
  }

  public enum Pull: Equatable, Sendable {
    case resting
    case pulling(Int)
    /// The clock ticked during pull `Int`, so another starts when it ends: one pull at a time.
    case pullingThenAgain(Int)
  }

  public enum Event: Equatable, Sendable {
    case cameToFront
    case wentAway
    case paired
    case unpaired
    case ticked(clock: Int)
    case pulled(Int)
  }

  public enum Output: Equatable, Sendable {
    /// Opens the room's socket, or leaves it be while it is open or reconnecting.
    case follow
    case unfollow
    case pull(Int)
    /// Reports `ticked(clock:)` after ``PartnerSyncMachine/every``.
    case tick(clock: Int)
  }

  public static let every = Duration.seconds(15)

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state.mode, event) {
    case (.away(let paired), .cameToFront):
      return paired ? start(state) : (State(mode: .unpaired, serial: state.serial), [])
    case (.away, .paired):
      return (State(mode: .away(paired: true), serial: state.serial), [])
    case (.away, .unpaired):
      return (State(mode: .away(paired: false), serial: state.serial), [])

    case (.unpaired, .paired):
      return start(state)
    case (.unpaired, .wentAway):
      return (State(mode: .away(paired: false), serial: state.serial), [])

    case (.following, .wentAway):
      return (State(mode: .away(paired: true), serial: state.serial), [.unfollow])
    case (.following, .unpaired):
      return (State(mode: .unpaired, serial: state.serial), [.unfollow])

    case (.following(var following), .ticked(let clock)) where clock == following.clock:
      var serial = state.serial + 1
      following.clock = serial
      var outputs: [Output] = [.follow, .tick(clock: serial)]
      switch following.pull {
      case .resting:
        serial += 1
        following.pull = .pulling(serial)
        outputs.append(.pull(serial))
      case .pulling(let id), .pullingThenAgain(let id):
        following.pull = .pullingThenAgain(id)
      }
      return (State(mode: .following(following), serial: serial), outputs)

    case (.following(var following), .pulled(let id)):
      switch following.pull {
      case .pulling(id):
        following.pull = .resting
        return (State(mode: .following(following), serial: state.serial), [])
      case .pullingThenAgain(id):
        following.pull = .pulling(state.serial + 1)
        return (
          State(mode: .following(following), serial: state.serial + 1), [.pull(state.serial + 1)]
        )
      case .resting, .pulling, .pullingThenAgain:
        return (state, [])
      }

    case (.away, .wentAway),
      (.away, .ticked),
      (.away, .pulled),
      (.unpaired, .cameToFront),
      (.unpaired, .unpaired),
      (.unpaired, .ticked),
      (.unpaired, .pulled),
      (.following, .cameToFront),
      (.following, .paired),
      (.following, .ticked):
      return (state, [])
    }
  }

  /// Follows and pulls at once, then on the clock.
  private static func start(_ state: State) -> (State, [Output]) {
    let clock = state.serial + 1
    let pull = state.serial + 2
    return (
      State(mode: .following(Following(clock: clock, pull: .pulling(pull))), serial: pull),
      [.follow, .pull(pull), .tick(clock: clock)]
    )
  }
}
