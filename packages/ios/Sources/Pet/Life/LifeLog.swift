import Foundation

/// The events one phone holds. Merging is by ID, so the same event from the room, from the
/// partner's frame and from this phone counts once, and the order they come in never matters.
public struct LifeLog: Codable, Hashable, Sendable {
  public private(set) var events: [UUID: LifeEvent] = [:]
  /// The earliest event ever seen, kept after the event itself is pruned.
  public private(set) var born: Date?

  public init(_ events: some Sequence<LifeEvent> = []) {
    merge(events)
  }

  /// Adds what it does not have yet. A copy from the room replaces this phone's own, so both
  /// phones end with the room's time for it.
  public mutating func merge(_ incoming: some Sequence<LifeEvent>) {
    for event in incoming {
      events[event.id] = event
      born = min(born ?? event.at, event.at)
    }
  }

  /// Forgets what is too old to matter to `config`'s horizon at `now`.
  public mutating func prune(now: Date, config: LifeConfig = .standard) {
    let oldest = now.addingTimeInterval(-(config.horizonHours + config.stepHours) * 3600)
    events = events.filter { $0.value.at >= oldest }
  }

  /// The device that last did something other than `me`: the partner, as far as this phone can
  /// tell.
  public func partner(of me: String) -> String? {
    events.values.filter { $0.by != me }.max(by: LifeEvent.precedes)?.by
  }

  public var all: [LifeEvent] { events.values.sorted(by: LifeEvent.precedes) }
}
