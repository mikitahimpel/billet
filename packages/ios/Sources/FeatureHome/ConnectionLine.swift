/// The one line of connection status shown on Home and in Settings.
enum ConnectionLine: Hashable, Sendable {
  case connecting
  case reconnecting
  case partnerAway
  case partnerHere
  case refused

  init(status: NoteDelivery.Status, hasConnected: Bool) {
    switch status {
    case .connecting: self = hasConnected ? .reconnecting : .connecting
    case .partnerAway: self = .partnerAway
    case .partnerHere: self = .partnerHere
    case .refused: self = .refused
    }
  }

  var text: String {
    switch self {
    case .connecting: "Connecting…"
    case .reconnecting: "Connection lost. Reconnecting…"
    case .partnerAway: "Partner away"
    case .partnerHere: "Partner here"
    case .refused: "This room is full"
    }
  }
}
