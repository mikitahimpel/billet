import Foundation
import Observation
import Pet

/// The pet's life on this phone: the events it holds, kept in `defaults`, and the state worked
/// out from them on a slow tick. The state itself is never stored.
///
/// For tuning it can run its own clock faster than real time. Events added from the debug
/// overlay stay on this phone and are dropped when the clock goes back to real time, so a
/// speeded-up test never reaches the partner.
@MainActor
@Observable
public final class PetLifeModel {
  public private(set) var log: LifeLog
  public private(set) var state: LifeState
  public private(set) var drive = LifeDrive()
  /// How many times faster than real time the debug clock runs.
  public private(set) var speed: Double = 1
  /// Events from the debug overlay, kept apart from the real ones.
  public private(set) var debugEvents: [LifeEvent] = []

  public let me: String
  public let config: LifeConfig

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let key: String
  @ObservationIgnored private let clock: @Sendable () -> Date
  @ObservationIgnored private let fallbackPartner: String?
  @ObservationIgnored private var focus: NeedFocus
  @ObservationIgnored private var anchor: (real: Date, simulated: Date)?
  /// Spans when nothing falls, read on each tick.
  @ObservationIgnored public var frozen: () -> [DateInterval] = { [] }

  /// - Parameter fallbackPartner: The partner's device until one of its events has been seen,
  ///   such as the fake partner's.
  public init(
    me: String, fallbackPartner: String? = nil, config: LifeConfig = .standard,
    defaults: UserDefaults = .standard, key: String = "life.events",
    clock: @escaping @Sendable () -> Date = { .now }
  ) {
    self.me = me
    self.fallbackPartner = fallbackPartner
    self.config = config
    self.defaults = defaults
    self.key = key
    self.clock = clock
    focus = NeedFocus(config: config, seed: UInt64.random(in: 1...UInt64.max))
    log =
      defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LifeLog.self, from: $0) }
      ?? LifeLog()
    state = PetLife.state(
      events: [], now: clock(), context: LifeContext(partners: [me], utcOffset: 0), config: config)
    refresh()
  }

  /// The time the life is read at: real time, or the debug clock while it runs fast.
  public var now: Date {
    guard let anchor else { return clock() }
    return anchor.simulated.addingTimeInterval(clock().timeIntervalSince(anchor.real) * speed)
  }

  public var context: LifeContext {
    let partner = log.partner(of: me) ?? fallbackPartner
    return LifeContext(
      partners: Set([me] + (partner.map { [$0] } ?? [])),
      utcOffset: TimeZone.current.secondsFromGMT(for: now), frozen: frozen(),
      born: [log.born, debugEvents.first?.at].compactMap(\.self).min())
  }

  /// Makes an event of this phone's, keeps it and returns it for the room.
  @discardableResult
  public func record(_ kind: LifeEvent.Kind, id: UUID = UUID()) -> LifeEvent {
    let event = LifeEvent(id: id, kind: kind, by: me, at: clock())
    receive([event])
    return event
  }

  /// Takes events from the room or the partner.
  public func receive(_ events: [LifeEvent]) {
    guard !events.isEmpty else { return }
    log.merge(events)
    log.prune(now: clock(), config: config)
    defaults.set(try? JSONEncoder().encode(log), forKey: key)
    refresh()
  }

  /// Works the state out again for `now`.
  public func refresh() {
    state = PetLife.state(
      events: log.all + debugEvents, now: now, context: context, config: config)
    let focused = focus.update(state.needs)
    drive = LifeDrive(asleep: state.asleep, focus: focused)
  }

  /// Runs the debug clock at `speed`, or back at real time for 1, which drops the debug events.
  public func setSpeed(_ speed: Double) {
    if speed <= 1 {
      anchor = nil
      debugEvents = []
      self.speed = 1
    } else {
      anchor = (clock(), now)
      self.speed = speed
    }
    refresh()
  }

  /// An event from the debug overlay, by this phone or as the partner, at the debug clock's time.
  public func debug(_ kind: LifeEvent.Kind, asPartner: Bool) {
    let by = asPartner ? (log.partner(of: me) ?? fallbackPartner ?? "partner") : me
    debugEvents.append(LifeEvent(kind: kind, by: by, at: now))
    refresh()
  }

  /// How long to wait between ticks: slow in real time, quick when the clock runs fast.
  public var tick: Duration { speed > 1 ? .milliseconds(250) : .seconds(20) }

  /// Refreshes on ``tick`` until cancelled.
  public func run() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: tick)
      refresh()
    }
  }
}
