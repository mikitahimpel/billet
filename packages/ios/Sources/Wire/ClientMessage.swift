/// Provisional until the realtime protocol is built.
public enum ClientMessage: Codable, Hashable, Sendable {
  /// Reconnect, asking for everything after `lastSeq`.
  case resume(lastSeq: Int)
  case stroke(Stroke)
  case presence(PresenceState)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case lastSeq
    case stroke
    case state
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Resume":
      self = .resume(lastSeq: try container.decode(Int.self, forKey: .lastSeq))
    case "Stroke":
      self = .stroke(try container.decode(Stroke.self, forKey: .stroke))
    case "Presence":
      self = .presence(try container.decode(PresenceState.self, forKey: .state))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .resume(let lastSeq):
      try container.encode("Resume", forKey: .tag)
      try container.encode(lastSeq, forKey: .lastSeq)
    case .stroke(let stroke):
      try container.encode("Stroke", forKey: .tag)
      try container.encode(stroke, forKey: .stroke)
    case .presence(let state):
      try container.encode("Presence", forKey: .tag)
      try container.encode(state, forKey: .state)
    }
  }
}
