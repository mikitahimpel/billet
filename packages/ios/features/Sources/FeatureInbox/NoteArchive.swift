import Foundation
import Persistence

/// The notes kept on this device, newest first, in one JSON file.
public actor NoteArchive {
  public static let fileName = "notes.json"
  /// Oldest notes fall off past this, which keeps the rewrite on each new note small.
  public static let limit = 200

  /// Where the notes are kept, which the drawing of the day shares.
  public nonisolated let storage: AppGroupStorage
  private var loaded: [NoteRecord]?

  public init(storage: AppGroupStorage) {
    self.storage = storage
  }

  /// All notes, newest first.
  public func notes() throws(PersistenceError) -> [NoteRecord] {
    if let loaded { return loaded }
    let stored = try storage.readJSON([NoteRecord].self, named: Self.fileName) ?? []
    loaded = stored
    return stored
  }

  /// Adds `note` and returns the updated list, newest first.
  @discardableResult
  public func add(_ note: NoteRecord) throws(PersistenceError) -> [NoteRecord] {
    var updated = try notes()
    let position = updated.firstIndex { $0.date <= note.date } ?? updated.endIndex
    updated.insert(note, at: position)
    updated = Array(updated.prefix(Self.limit))
    try storage.writeJSON(updated, named: Self.fileName)
    loaded = updated
    return updated
  }

  /// Deletes every note from disk.
  public func erase() throws(PersistenceError) {
    try storage.remove(Self.fileName)
    loaded = []
  }
}
