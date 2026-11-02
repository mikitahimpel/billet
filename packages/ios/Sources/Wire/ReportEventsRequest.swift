/// The events the app may report about itself: a name and nothing else. The server stamps the time
/// and adds the pair, and it records `InviteCreated`, `PairClaimed` and `NoteSent` itself, so those
/// are not here and are refused if sent.
public enum ClientEventName: String, Codable, Hashable, Sendable, CaseIterable {
  /// The app came to the front. At most one per launch.
  case appOpened = "AppOpened"
  /// This phone now has a billet widget on a Home Screen or StandBy. Reported once.
  case widgetAdded = "WidgetAdded"
  /// The user watched the opening to the end.
  case openingWatched = "OpeningWatched"
  /// The user skipped the opening.
  case openingSkipped = "OpeningSkipped"
}

public struct ReportEventsRequest: Codable, Hashable, Sendable {
  /// At most `ReportEventsRequest.maxEvents`.
  public let events: [ClientEventName]

  public static let maxEvents = 20

  public init(events: [ClientEventName]) {
    self.events = events
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let events = try container.decode([ClientEventName].self, forKey: .events)
    guard events.count <= Self.maxEvents else {
      throw DecodingError.dataCorruptedError(
        forKey: .events, in: container,
        debugDescription: "at most \(Self.maxEvents) events per request")
    }
    self.events = events
  }

  private enum CodingKeys: String, CodingKey {
    case events
  }
}
