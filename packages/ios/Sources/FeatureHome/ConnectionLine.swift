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

  /// How long Home waits on a connection that is not there yet before saying so, so a short drop
  /// never flashes a line on screen.
  static let patience: Duration = .seconds(3)

  /// Whether Home holds the line back for ``patience`` before showing it.
  var waitsBeforeShowing: Bool {
    switch self {
    case .connecting, .reconnecting: true
    case .partnerAway, .partnerHere, .refused: false
    }
  }

  var text: String {
    switch self {
    case .connecting: "Connecting…"
    case .reconnecting: "Reconnecting…"
    case .partnerAway: "Partner away"
    case .partnerHere: "Partner here"
    case .refused: "This room is full"
    }
  }
}
