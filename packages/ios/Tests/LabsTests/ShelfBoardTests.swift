import FeatureInbox
import Foundation
import Testing

@testable import Labs

@Suite struct ShelfBoardTests {
  private func notes(_ count: Int) -> [NoteRecord] {
    (0..<count).map {
      NoteRecord(
        direction: $0.isMultiple(of: 2) ? .sent : .received,
        date: Date(timeIntervalSince1970: TimeInterval(1_000 * $0)), strokes: [])
    }
  }

  private func board(_ count: Int, streak: Int = 0, width: CGFloat = 370, noteWidth: CGFloat = 74)
    -> ShelfBoard
  {
    ShelfBoard(notes: notes(count), streak: streak, width: width, noteWidth: noteWidth)
  }

  private func noteIDs(_ board: ShelfBoard) -> [UUID] {
    board.shelves.flatMap(\.items).compactMap {
      if case .note(let placement) = $0 { placement.id } else { nil }
    }
  }

  private func days(_ board: ShelfBoard) -> [Int] {
    board.shelves.flatMap(\.items).compactMap {
      if case .slot(let day) = $0 { day } else { nil }
    }
  }

  @Test func theNewestNoteStandsForward() {
    let all = notes(5)
    let board = ShelfBoard(notes: all.shuffled(), streak: 0, width: 370, noteWidth: 74)
    #expect(board.forward?.id == all.last?.id)
  }

  @Test func theRestRunNewestFirstAndNoneIsLost() {
    let all = notes(200)
    let board = ShelfBoard(notes: all, streak: 0, width: 370, noteWidth: 74)
    #expect(noteIDs(board) == all.dropLast().reversed().map(\.id))
  }

  @Test func aThousandNotesAllFindAPlace() {
    let board = board(1_000)
    #expect(Set(noteIDs(board)).count == 999)
    #expect(board.shelves.allSatisfy { $0.items.count <= board.capacity })
  }

  @Test func noShelfButTheLastIsShort() {
    let board = board(30)
    #expect(board.shelves.dropLast().allSatisfy { $0.items.count == board.capacity })
  }

  @Test func capacityFollowsTheWidthOfANote() {
    #expect(board(1).capacity == 4)
    #expect(board(1, noteWidth: 120).capacity == 2)
    #expect(board(1, noteWidth: 500).capacity == 1)
  }

  @Test func withNoNotesTheShelfIsAllSlots() {
    let board = board(0, streak: 0)
    #expect(board.forward == nil)
    #expect(board.above == nil)
    #expect(days(board) == [1, 2, 3, 4])
  }

  @Test func oneNoteStandsForwardWithSlotsBelowIt() {
    let board = board(1, streak: 3)
    #expect(board.forward != nil)
    #expect(board.above == nil)
    #expect(days(board) == [4, 5, 6, 7])
  }

  @Test func slotsNumberTheNextDaysOfTheStreak() {
    #expect(days(board(3, streak: 19)) == [20, 21])
  }

  @Test func slotsFinishTheLastShelf() {
    let board = board(8, streak: 1)
    #expect(board.shelves.last?.items.count == board.capacity)
  }

  @Test func atLeastTwoDaysAreAlwaysOpen() {
    for count in 0...20 {
      #expect(days(board(count)).count >= ShelfBoard.leastSlots, "\(count) notes")
    }
  }

  @Test func onANarrowShelfEachDayStandsAlone() {
    let board = board(0, noteWidth: 500)
    #expect(board.capacity == 1)
    #expect(board.shelves.allSatisfy { $0.items.count == 1 })
    #expect(days(board).count == 1)
  }

  @Test func slotsStartAfterTheStreakEvenWhenItIsNegative() {
    #expect(days(board(0, streak: -4)).first == 1)
  }

  @Test func theShelvesMarkWholeWeeksTheStreakHasReached() {
    let marks = board(40, streak: 15).shelves.map(\.milestone)
    #expect(Array(marks.prefix(4)) == [nil, 7, 14, nil])
  }

  @Test func theFirstShelfIsNeverMarked() {
    #expect(board(40, streak: 300).shelves.first?.milestone == nil)
  }

  @Test func everyNoteLeansALittle() {
    for shelf in board(300).shelves {
      for case .note(let placement) in shelf.items {
        #expect(abs(placement.tilt) >= ShelfBoard.smallestTilt)
        #expect(abs(placement.tilt) <= ShelfBoard.largestTilt)
      }
    }
  }

  @Test func notesLeanBothWays() {
    let tilts = board(100).shelves.flatMap(\.items).compactMap { item -> Double? in
      if case .note(let placement) = item { placement.tilt } else { nil }
    }
    #expect(tilts.contains { $0 > 0 } && tilts.contains { $0 < 0 })
  }

  @Test func aNoteKeepsItsLeanAsMoreArrive() {
    let first = NoteRecord(direction: .sent, date: Date(timeIntervalSince1970: 1), strokes: [])
    #expect(ShelfBoard.Placement(note: first) == ShelfBoard.Placement(note: first))
    let later = ShelfBoard(notes: [first] + notes(9), streak: 0, width: 370, noteWidth: 74)
    let moved = later.shelves.flatMap(\.items).compactMap { item -> ShelfBoard.Placement? in
      if case .note(let placement) = item, placement.id == first.id { placement } else { nil }
    }
    #expect(moved.first?.tilt == ShelfBoard.Placement(note: first).tilt)
  }

  @Test func notesKeepTheirSizeAtOrdinaryText() {
    #expect(ShelfBoard.noteWidth(scaled: 74, width: 370) == 74)
  }

  @Test func theLargestTextStillLeavesTwoNotesToAShelf() {
    let width = ShelfBoard.noteWidth(scaled: 210, width: 370)
    #expect(board(4, noteWidth: width).capacity == 2)
  }

  @Test func aFullShelfSpreadsToBothEdges() {
    let board = board(9)
    let spacing = board.spacing(width: 370, noteWidth: 74)
    #expect(4 * 74 + 3 * spacing == 370)
  }

  @Test func notesNeverStandCloserThanTheGap() {
    let board = board(9, width: 370, noteWidth: 90)
    #expect(board.capacity == 3)
    #expect(board.spacing(width: 270, noteWidth: 90) == ShelfBoard.gap)
  }

  @Test func someNotesAreOnWarmerPaper() {
    let papers = board(100).shelves.flatMap(\.items).compactMap { item -> Bool? in
      if case .note(let placement) = item { placement.isWarmPaper } else { nil }
    }
    #expect(papers.contains(true) && papers.contains(false))
  }

  @Test func theCupsStandBesideTheForwardNoteOnlyWhenThereIsRoom() {
    #expect(board(4).cupsBeside)
    #expect(!board(4, noteWidth: 180).cupsBeside)
  }
}
