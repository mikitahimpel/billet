import FeatureInbox
import Foundation

/// Where the one shared cat is: with whoever received the last note.
///
/// Derived from the notes kept on this device, so nothing new is sent or stored. The phone that
/// sent the last note sees the cat gone; it comes back when the partner sends one.
public enum OvernightStay: Equatable, Sendable {
  case here
  /// The cat went with the last note this device sent, at `since`.
  case withPartner(since: Date)

  /// - Parameter notes: Every note kept, in any order.
  public static func place(after notes: [NoteRecord]) -> OvernightStay {
    guard let last = notes.max(by: { $0.date < $1.date }) else { return .here }
    switch last.direction {
    case .sent: return .withPartner(since: last.date)
    case .received: return .here
    }
  }

  public var isAway: Bool {
    switch self {
    case .here: false
    case .withPartner: true
    }
  }
}
