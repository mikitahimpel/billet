import Foundation
import Wire

/// One note kept on this device, in either direction.
public struct NoteRecord: Codable, Hashable, Identifiable, Sendable {
  public enum Direction: String, Codable, Hashable, Sendable {
    case sent
    case received
  }

  public let id: UUID
  public let direction: Direction
  /// When this device sent or received it. The room does not timestamp notes.
  public let date: Date
  public let strokes: [Stroke]

  public init(id: UUID = UUID(), direction: Direction, date: Date, strokes: [Stroke]) {
    self.id = id
    self.direction = direction
    self.date = date
    self.strokes = strokes
  }
}
