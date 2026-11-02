import Foundation

/// The cat's trip with a note, from this phone's side: it goes out with the note, and once the
/// partner has opened it the cat is back with an empty satchel, for a while.
public struct CatReturn: Equatable, Sendable {
  public enum Phase: Equatable, Sendable {
    case idle
    /// Carrying the note `note`, not opened yet.
    case out(note: UUID)
    /// Back since `at`, because the partner opened `note`.
    case back(note: UUID, at: Date)
  }

  /// How long the empty satchel stays on show.
  public static let showFor: TimeInterval = 12 * 3600

  public private(set) var phase = Phase.idle

  public init() {}

  /// This phone sent a note. The cat is out with it, whatever it was doing.
  public mutating func sent(_ note: UUID) {
    phase = .out(note: note)
  }

  /// The partner opened `note`. Only the note the cat carries brings it back: an older note being
  /// opened late changes nothing.
  public mutating func opened(_ note: UUID, at date: Date) {
    guard case .out(let carried) = phase, carried == note else { return }
    phase = .back(note: note, at: date)
  }

  /// True while the empty satchel is shown.
  public func isBack(now: Date) -> Bool {
    guard case .back(_, let at) = phase else { return false }
    return now >= at && now.timeIntervalSince(at) < Self.showFor
  }
}
