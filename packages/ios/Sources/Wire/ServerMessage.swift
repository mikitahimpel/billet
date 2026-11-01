/// Provisional until the realtime protocol is built. `seq` supports reconnect.
public enum ServerMessage: Codable, Hashable, Sendable {
  case stroke(seq: Int, stroke: Stroke)
  case presence(PresenceState)
  case noteReceived(seq: Int, note: Note)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case seq
    case stroke
    case state
    case note
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Stroke":
      self = .stroke(
        seq: try container.decode(Int.self, forKey: .seq),
        stroke: try container.decode(Stroke.self, forKey: .stroke))
    case "Presence":
      self = .presence(try container.decode(PresenceState.self, forKey: .state))
    case "NoteReceived":
      self = .noteReceived(
        seq: try container.decode(Int.self, forKey: .seq),
        note: try container.decode(Note.self, forKey: .note))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .stroke(let seq, let stroke):
      try container.encode("Stroke", forKey: .tag)
      try container.encode(seq, forKey: .seq)
      try container.encode(stroke, forKey: .stroke)
    case .presence(let state):
      try container.encode("Presence", forKey: .tag)
      try container.encode(state, forKey: .state)
    case .noteReceived(let seq, let note):
      try container.encode("NoteReceived", forKey: .tag)
      try container.encode(seq, forKey: .seq)
      try container.encode(note, forKey: .note)
    }
  }
}
