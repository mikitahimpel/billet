import BilletKit

/// Keeps this phone up to date with the partner while the app is in front and paired. The room's
/// socket is the path: everything is pulled once each time it opens. A clock checks it: while it is
/// healthy a small summary is pulled every ``PartnerSyncMachine/healthyEvery``; while it is down
/// or silent everything is pulled, at ``PartnerSyncMachine/silentEvery(failures:)``. Nothing is
/// pulled while the app is away. Every tick, check and pull carries a number from `serial`; one
/// that is not current is stale and changes nothing.
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
    /// The tick or check this clock waits for.
    public var clock: Int
    public var pull: Pull
    public var socket: Socket

    public init(clock: Int, pull: Pull, socket: Socket) {
      self.clock = clock
      self.pull = pull
      self.socket = socket
    }
  }

  public enum Socket: Equatable, Sendable {
    /// Not open yet since the app came to the front or the pair began.
    case opening
    case healthy
    /// Down or unanswered at this many checks in a row.
    case silent(failures: Int)
  }

  public enum Kind: Equatable, Sendable, Comparable {
    /// The few reads that show most of what the partner did: the Inbox count, the riddles and the
    /// wallet.
    case summary
    case everything
  }

  public enum Pull: Equatable, Sendable {
    case resting
    case pulling(Int)
    /// Asked for again during pull `Int`, so a pull of `Kind` starts when it ends: one at a time.
    case pullingThen(Int, Kind)
  }

  public enum Event: Equatable, Sendable {
    case cameToFront
    case wentAway
    case paired
    case unpaired
    /// The room's socket opened, the first time or after a drop.
    case socketOpened
    case ticked(clock: Int)
    /// Whether the socket was heard from or answered a ping.
    case checked(clock: Int, healthy: Bool)
    case pulled(Int)
  }

  public enum Output: Equatable, Sendable {
    /// Opens the room's socket, or leaves it be while it is open or reconnecting.
    case follow
    case unfollow
    case pull(Int, Kind)
    /// Reports `ticked(clock:)` after `after`.
    case tick(clock: Int, after: Duration)
    /// Reports `checked(clock:healthy:)`: healthy if a frame came within ``quietLimit``, else if
    /// the socket answers a ping.
    case check(clock: Int)
  }

  /// How long the socket may say nothing before it is pinged.
  public static let quietLimit = Duration.seconds(45)
  /// How long a socket that just started opening gets before it counts as down.
  public static let openingGrace = Duration.seconds(5)
  public static let healthyEvery = Duration.seconds(60)

  /// 15 s, then 30 s, then 60 s.
  public static func silentEvery(failures: Int) -> Duration {
    .seconds(15 << min(max(failures - 1, 0), 2))
  }

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

    case (.following(var following), .socketOpened):
      var serial = state.serial + 1
      following.clock = serial
      following.socket = .healthy
      var outputs: [Output] = [.tick(clock: serial, after: healthyEvery)]
      outputs += ask(.everything, &following, serial: &serial)
      return (State(mode: .following(following), serial: serial), outputs)

    case (.following(let following), .ticked(let clock)) where clock == following.clock:
      return (state, [.follow, .check(clock: clock)])

    case (.following(var following), .checked(let clock, let healthy))
    where clock == following.clock:
      var serial = state.serial + 1
      following.clock = serial
      let delay: Duration
      let kind: Kind
      if healthy {
        following.socket = .healthy
        delay = healthyEvery
        kind = .summary
      } else {
        let failures: Int
        switch following.socket {
        case .opening, .healthy: failures = 1
        case .silent(let before): failures = before + 1
        }
        following.socket = .silent(failures: failures)
        delay = silentEvery(failures: failures)
        kind = .everything
      }
      var outputs: [Output] = [.tick(clock: serial, after: delay)]
      outputs += ask(kind, &following, serial: &serial)
      return (State(mode: .following(following), serial: serial), outputs)

    case (.following(var following), .pulled(let id)):
      switch following.pull {
      case .pulling(id):
        following.pull = .resting
        return (State(mode: .following(following), serial: state.serial), [])
      case .pullingThen(id, let kind):
        let next = state.serial + 1
        following.pull = .pulling(next)
        return (State(mode: .following(following), serial: next), [.pull(next, kind)])
      case .resting, .pulling, .pullingThen:
        return (state, [])
      }

    case (.away, .wentAway),
      (.away, .socketOpened),
      (.away, .ticked),
      (.away, .checked),
      (.away, .pulled),
      (.unpaired, .cameToFront),
      (.unpaired, .unpaired),
      (.unpaired, .socketOpened),
      (.unpaired, .ticked),
      (.unpaired, .checked),
      (.unpaired, .pulled),
      (.following, .cameToFront),
      (.following, .paired),
      (.following, .ticked),
      (.following, .checked):
      return (state, [])
    }
  }

  /// Follows the socket; its opening pulls. A socket still shut after ``openingGrace`` is checked
  /// and found down, which pulls without it.
  private static func start(_ state: State) -> (State, [Output]) {
    let clock = state.serial + 1
    return (
      State(
        mode: .following(Following(clock: clock, pull: .resting, socket: .opening)), serial: clock),
      [.follow, .tick(clock: clock, after: openingGrace)]
    )
  }

  /// Starts a pull of `kind`, or one after the pull under way, of the larger kind asked.
  private static func ask(_ kind: Kind, _ following: inout Following, serial: inout Int)
    -> [Output]
  {
    switch following.pull {
    case .resting:
      serial += 1
      following.pull = .pulling(serial)
      return [.pull(serial, kind)]
    case .pulling(let id):
      following.pull = .pullingThen(id, kind)
      return []
    case .pullingThen(let id, let queued):
      following.pull = .pullingThen(id, max(queued, kind))
      return []
    }
  }
}
