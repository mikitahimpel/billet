import Foundation
import Testing
import Wire

@testable import FeatureInbox

@Suite struct DailyBoardTests {
  private let prompt = DailyPromptText(id: "where-you-are", text: "Draw where you are right now")
  private let mine = [Stroke(color: "#000000", width: 0.02, points: [Point(x: 0.1, y: 0.1)])]
  private let theirs = [Stroke(color: "#A5442B", width: 0.02, points: [Point(x: 0.9, y: 0.9)])]

  private func board(prompts day: String = "2026-11-04") -> DailyBoard {
    var board = DailyBoard()
    board.promptsReceived([day: prompt])
    return board
  }

  @Test func theRoomsPromptIsTodays() {
    #expect(board().prompt(on: "2026-11-04") == prompt)
    #expect(board().prompt(on: "2026-11-05") == nil)
  }

  @Test func drawingShowsAtOnceAndKeepsTheFirst() {
    var board = board()
    board.drew(mine, on: "2026-11-04")
    board.drew(theirs, on: "2026-11-04")
    #expect(board.hasDrawn(on: "2026-11-04"))
    #expect(board.entry(on: "2026-11-04")?.mine == mine)
  }

  @Test func aDayWithoutAPromptCannotBeDrawn() {
    var board = DailyBoard()
    board.drew(mine, on: "2026-11-04")
    #expect(!board.hasDrawn(on: "2026-11-04"))
  }

  @Test func aLateReplayDoesNotUndoThisPhonesDrawing() {
    var board = board()
    board.drew(mine, on: "2026-11-04")
    board.received(DailyEntry(day: "2026-11-04", prompt: prompt, theirsDrawn: true))
    let entry = board.entry(on: "2026-11-04")
    #expect(entry?.mine == mine)
    #expect(entry?.theirsDrawn == true)
    #expect(entry?.theirs == nil)
  }

  @Test func aDayCountsForTheStreakOnceBothDrew() {
    var board = board()
    board.received(DailyEntry(day: "2026-11-04", prompt: prompt, theirsDrawn: true))
    #expect(board.sharedDays.isEmpty)
    board.drew(mine, on: "2026-11-04")
    #expect(board.sharedDays == ["2026-11-04"])
  }

  @Test func theRevealWaitsForBothDrawingsAndPlaysOnce() {
    var board = board()
    board.drew(mine, on: "2026-11-04")
    #expect(board.pendingReveal == nil)
    board.received(DailyEntry(day: "2026-11-04", prompt: prompt, mine: mine, theirs: theirs))
    #expect(board.pendingReveal?.day == "2026-11-04")
    board.revealShown("2026-11-04")
    #expect(board.pendingReveal == nil)
  }

  @Test func theArchiveIsNewestFirstAndSkipsUndrawnDays() {
    var board = DailyBoard()
    board.received(DailyEntry(day: "2026-11-02", prompt: prompt, mine: mine))
    board.received(DailyEntry(day: "2026-11-03", prompt: prompt))
    board.received(DailyEntry(day: "2026-11-04", prompt: prompt, theirsDrawn: true))
    #expect(board.archive.map(\.day) == ["2026-11-04", "2026-11-02"])
  }

  @Test func onlyTheNewestDaysAreKept() {
    var board = DailyBoard()
    for offset in 0..<(DailyBoard.keptDays + 3) {
      let day = String(format: "2026-%02d-%02d", 1 + offset / 28, 1 + offset % 28)
      board.received(DailyEntry(day: day, prompt: prompt, mine: mine))
    }
    #expect(board.entries.count == DailyBoard.keptDays)
    #expect(board.entry(on: "2026-01-01") == nil)
  }

  @Test func theBoardSurvivesTheArchive() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let archive = DailyArchive(storage: .directory(directory))
    var board = board()
    board.drew(mine, on: "2026-11-04")
    await archive.save(board)
    #expect(await archive.load() == board)
  }
}
