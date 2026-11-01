import Foundation
import Persistence
import Testing
import Wire

@testable import FeatureInbox

@Suite("NoteArchive")
struct NoteArchiveTests {
  private let directory = FileManager.default.temporaryDirectory
    .appending(path: UUID().uuidString, directoryHint: .isDirectory)
  private var storage: AppGroupStorage { .directory(directory) }
  private let strokes = [
    Stroke(color: "#112233", width: 0.01, points: [Point(x: 0.25, y: 0.5), Point(x: 0.75, y: 1.5)])
  ]

  private func note(_ direction: NoteRecord.Direction = .sent, at seconds: Double) -> NoteRecord {
    NoteRecord(
      direction: direction, date: Date(timeIntervalSince1970: seconds), strokes: strokes)
  }

  @Test func startsEmpty() async throws {
    #expect(try await NoteArchive(storage: storage).notes().isEmpty)
  }

  @Test func keepsNewestFirstWhateverTheOrderAdded() async throws {
    let archive = NoteArchive(storage: storage)
    let middle = note(at: 20)
    let newest = note(.received, at: 30)
    let oldest = note(at: 10)
    try await archive.add(middle)
    try await archive.add(newest)
    try await archive.add(oldest)
    #expect(try await archive.notes() == [newest, middle, oldest])
  }

  @Test func survivesARestartWithTheDrawingIntact() async throws {
    let saved = note(.received, at: 10)
    try await NoteArchive(storage: storage).add(saved)
    let reopened = try await NoteArchive(storage: storage).notes()
    #expect(reopened == [saved])
    #expect(reopened.first?.strokes == strokes)
    #expect(reopened.first?.direction == .received)
  }

  @Test func dropsTheOldestPastTheLimit() async throws {
    let archive = NoteArchive(storage: storage)
    for second in 0...NoteArchive.limit {
      try await archive.add(note(at: Double(second)))
    }
    let kept = try await archive.notes()
    #expect(kept.count == NoteArchive.limit)
    #expect(kept.last?.date == Date(timeIntervalSince1970: 1))
  }

  @Test func eraseRemovesTheFile() async throws {
    let archive = NoteArchive(storage: storage)
    try await archive.add(note(at: 10))
    try await archive.erase()
    #expect(try await archive.notes().isEmpty)
    #expect(try storage.read(NoteArchive.fileName) == nil)
    #expect(try await NoteArchive(storage: storage).notes().isEmpty)
  }

  @Test func eraseOnAnEmptyArchiveIsFine() async throws {
    try await NoteArchive(storage: storage).erase()
  }

  @Test func aCorruptFileIsReportedNotHidden() async throws {
    try storage.write(NoteArchive.fileName, Data("nope".utf8))
    await #expect(throws: PersistenceError.self) {
      try await NoteArchive(storage: storage).notes()
    }
  }
}
