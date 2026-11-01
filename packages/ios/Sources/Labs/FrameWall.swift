import FeatureInbox
import Foundation

/// The notes hung in frames: a few, oldest hung first, each a note the partner sent.
public struct FrameWall: Codable, Equatable, Sendable {
  public static let capacity = 3

  /// Note IDs, in the order they were hung.
  public private(set) var hung: [UUID]

  public init(hung: [UUID] = []) {
    self.hung = Array(hung.prefix(Self.capacity))
  }

  /// Only a note received from the partner can be framed.
  public static func canHang(_ note: NoteRecord) -> Bool {
    note.direction == .received
  }

  public func isHung(_ id: UUID) -> Bool { hung.contains(id) }

  /// Hangs `note`. When the wall is full the longest-hung frame comes down. Hanging a note that is
  /// already up changes nothing.
  public mutating func hang(_ note: NoteRecord) {
    guard Self.canHang(note), !isHung(note.id) else { return }
    hung.append(note.id)
    if hung.count > Self.capacity { hung.removeFirst(hung.count - Self.capacity) }
  }

  public mutating func takeDown(_ id: UUID) {
    hung.removeAll { $0 == id }
  }

  /// Takes down frames whose notes are gone, such as notes that fell off the end of the archive.
  public mutating func prune(keeping existing: Set<UUID>) {
    hung.removeAll { !existing.contains($0) }
  }
}
