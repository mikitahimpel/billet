import FeatureInbox
import Foundation
import Testing

@testable import Labs

@Suite struct FrameWallTests {
  private func note(_ direction: NoteRecord.Direction = .received) -> NoteRecord {
    NoteRecord(direction: direction, date: .now, strokes: [])
  }

  @Test func onlyReceivedNotesCanBeFramed() {
    var wall = FrameWall()
    wall.hang(note(.sent))
    #expect(wall.hung.isEmpty)
    let theirs = note()
    wall.hang(theirs)
    #expect(wall.isHung(theirs.id))
  }

  @Test func hangingTheSameNoteTwiceChangesNothing() {
    var wall = FrameWall()
    let theirs = note()
    wall.hang(theirs)
    wall.hang(theirs)
    #expect(wall.hung == [theirs.id])
  }

  @Test func aFullWallLosesItsOldestFrame() {
    var wall = FrameWall()
    let notes = (0..<4).map { _ in note() }
    for note in notes { wall.hang(note) }
    #expect(wall.hung == notes.dropFirst().map(\.id))
    #expect(wall.hung.count == FrameWall.capacity)
  }

  @Test func takingDownLeavesTheRest() {
    var wall = FrameWall()
    let (a, b) = (note(), note())
    wall.hang(a)
    wall.hang(b)
    wall.takeDown(a.id)
    #expect(wall.hung == [b.id])
  }

  @Test func framesOfVanishedNotesComeDown() {
    var wall = FrameWall()
    let (a, b) = (note(), note())
    wall.hang(a)
    wall.hang(b)
    wall.prune(keeping: [b.id])
    #expect(wall.hung == [b.id])
  }

  @Test func theWallSurvivesEncoding() throws {
    var wall = FrameWall()
    wall.hang(note())
    let again = try JSONDecoder().decode(FrameWall.self, from: JSONEncoder().encode(wall))
    #expect(again == wall)
  }

  @Test func aStoredWallLongerThanTheCapacityIsTrimmed() {
    #expect(FrameWall(hung: (0..<9).map { _ in UUID() }).hung.count == FrameWall.capacity)
  }

  @MainActor @Test func theStoreKeepsTheWallBetweenLaunchesAndPerKey() {
    let defaults = UserDefaults(suiteName: "frames-\(UUID().uuidString)") ?? .standard
    let theirs = note()
    let first = FramedNotes(defaults: defaults)
    first.hang(theirs)
    #expect(FramedNotes(defaults: defaults).wall.isHung(theirs.id))
    #expect(!FramedNotes(defaults: defaults, key: "other").wall.isHung(theirs.id))
    first.prune(keeping: [])
    #expect(FramedNotes(defaults: defaults).wall.hung.isEmpty)
  }
}
