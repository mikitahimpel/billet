import Foundation
import Pet

/// The pet's life as the widget needs it: the events and the context, so each timeline entry
/// works the state out for its own hour with the same formulas as the app.
public struct WidgetLife: Codable, Equatable, Sendable {
  public var events: [LifeEvent]
  public var partners: [String]
  public var utcOffset: Int
  public var born: Date?
  public var frozen: [DateInterval]
  public var config: LifeConfig

  public init(
    events: [LifeEvent], context: LifeContext, config: LifeConfig = .standard
  ) {
    self.events = events
    partners = context.partners.sorted()
    utcOffset = context.utcOffset
    born = context.born
    frozen = context.frozen
    self.config = config
  }

  public var context: LifeContext {
    LifeContext(partners: Set(partners), utcOffset: utcOffset, frozen: frozen, born: born)
  }

  public func state(at now: Date) -> LifeState {
    PetLife.state(events: events, now: now, context: context, config: config)
  }

  /// The need the cat thinks of at `now`, the one a widget shows in a bubble: the lowest, when it
  /// is low and the cat is awake.
  public func thought(at now: Date) -> PetNeed? {
    let state = state(at: now)
    let lowest = state.needs.lowest
    guard !state.asleep, lowest.value < config.lowBelow else { return nil }
    return lowest.need
  }
}
