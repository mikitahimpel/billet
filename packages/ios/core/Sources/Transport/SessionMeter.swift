import Wire

/// Turns the app coming to the front and leaving it into `AppOpened`, once, and a `SessionEnded`
/// for each stay. A stay the system ends without sending the app to the background is not counted.
public struct SessionMeter: Sendable {
  public enum Phase: Sendable {
    case front
    /// Still on screen but not in use: the app switcher, a system alert. The stay goes on.
    case aside
    case away
  }

  private var began: ContinuousClock.Instant?
  private var opened = false

  public init() {}

  public mutating func moved(to phase: Phase, at now: ContinuousClock.Instant) -> [ClientEvent] {
    switch phase {
    case .front:
      guard began == nil else { return [] }
      began = now
      guard !opened else { return [] }
      opened = true
      return [ClientEvent(.appOpened)]
    case .aside:
      return []
    case .away:
      guard let began else { return [] }
      self.began = nil
      return [ClientEvent(.sessionEnded, detail: SessionLength(now - began).rawValue)]
    }
  }
}
