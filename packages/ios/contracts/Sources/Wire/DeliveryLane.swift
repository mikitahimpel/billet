public enum DeliveryLane: Codable, Hashable, Sendable {
  case webSocket
  case widgetPush
  case alertPush
  case timelineRefresh
  case liveActivityPush

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "WebSocket": self = .webSocket
    case "WidgetPush": self = .widgetPush
    case "AlertPush": self = .alertPush
    case "TimelineRefresh": self = .timelineRefresh
    case "LiveActivityPush": self = .liveActivityPush
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .webSocket: try container.encode("WebSocket", forKey: .tag)
    case .widgetPush: try container.encode("WidgetPush", forKey: .tag)
    case .alertPush: try container.encode("AlertPush", forKey: .tag)
    case .timelineRefresh: try container.encode("TimelineRefresh", forKey: .tag)
    case .liveActivityPush: try container.encode("LiveActivityPush", forKey: .tag)
    }
  }
}
