import Foundation
import Wire

/// A note held back until a set time.
public struct SealedNote: Codable, Equatable, Identifiable, Sendable {
  public enum Direction: String, Codable, Sendable {
    /// Drawn here, kept on this phone until it opens, then sent.
    case outgoing
    /// Drawn by the partner, shown closed until it opens, then read like any other.
    case incoming
  }

  public let id: UUID
  public let strokes: [Stroke]
  public let opensAt: Date
  public let direction: Direction

  public init(id: UUID = UUID(), strokes: [Stroke], opensAt: Date, direction: Direction) {
    self.id = id
    self.strokes = strokes
    self.opensAt = opensAt
    self.direction = direction
  }
}

/// The sealed notes waiting on this phone.
public struct SealedBox: Codable, Equatable, Sendable {
  public private(set) var notes: [SealedNote]

  public init(notes: [SealedNote] = []) {
    self.notes = notes
  }

  /// The next morning, `hour` o'clock in `calendar`: always on a later day than `now`, so a note
  /// sealed at one in the morning still waits a night.
  public static func tomorrowMorning(after now: Date, calendar: Calendar, hour: Int = 8) -> Date {
    let today = calendar.startOfDay(for: now)
    let tomorrow =
      calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
  }

  public mutating func seal(_ note: SealedNote) {
    notes.removeAll { $0.id == note.id }
    notes.append(note)
    notes.sort { $0.opensAt < $1.opensAt }
  }

  public func waiting(_ direction: SealedNote.Direction) -> [SealedNote] {
    notes.filter { $0.direction == direction }
  }

  /// Takes out every note whose time has come, soonest first, and returns them.
  public mutating func release(at now: Date) -> [SealedNote] {
    let due = notes.filter { $0.opensAt <= now }
    notes.removeAll { $0.opensAt <= now }
    return due
  }
}
