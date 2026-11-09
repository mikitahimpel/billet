/// The partner as the room sees them: `away` while they have no open socket, else what they last
/// said. Only the room sends it; a device says ``PresenceState``.
public enum PartnerPresence: String, Codable, Hashable, Sendable {
  case idle
  case drawing
  case away
}
