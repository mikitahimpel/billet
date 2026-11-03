import Foundation

/// Something a partner did for the pet, or the pet did, as both phones keep it. The life is a pure
/// function of these and the time, so two phones holding the same events show the same pet.
public struct LifeEvent: Codable, Hashable, Identifiable, Sendable {
  public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
    /// A treat or a meal.
    case feed
    /// A stroke from `by`.
    case pet
    /// A game with `by`: batting a finger, chasing a light.
    case play
    /// A note from `by`. It fills Loved for both partners.
    case note
    /// The pet was put to bed, or curled up.
    case sleep
    /// `by` shooed the cat off where it sat, the desk or the cardigan.
    case shoo
  }

  /// The ID of the room frame that carried it, so the same event from two paths counts once.
  public let id: UUID
  public let kind: Kind
  /// The device that did it.
  public let by: String
  /// Whole seconds, as the room's ISO timestamps carry it.
  public let at: Date

  public init(id: UUID = UUID(), kind: Kind, by: String, at: Date) {
    self.id = id
    self.kind = kind
    self.by = by
    self.at = Date(timeIntervalSince1970: (at.timeIntervalSince1970).rounded(.down))
  }

  /// The order every phone folds events in: by time, then by ID.
  static func precedes(_ a: LifeEvent, _ b: LifeEvent) -> Bool {
    a.at != b.at ? a.at < b.at : a.id.uuidString < b.id.uuidString
  }
}
