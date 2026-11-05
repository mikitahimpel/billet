import Foundation
import Testing
import Transport
import Wire

@testable import FeatureInbox

@Suite struct HistoryMachineTests {
  typealias M = HistoryMachine

  static func note(_ seq: Int, author: String = "me") -> HistoryNote {
    HistoryNote(
      seq: seq, authorID: author, sentAt: Date(timeIntervalSince1970: Double(seq)),
      content: .drawing([]))
  }

  @Test func theFirstLoadAsksFromTheStart() {
    let (state, outputs) = M.transition(.idle, .refreshed)
    #expect(state == .loading(notes: [], request: 1))
    #expect(outputs == [.loadPage(after: nil, request: 1)])
  }

  @Test func aShortPageEndsTheLoad() {
    var (state, _) = M.transition(.idle, .refreshed)
    let page = M.Page(notes: [Self.note(1), Self.note(2)], count: 2)
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .pageLoaded(page, request: 1))
    #expect(state == .loaded(notes: [Self.note(1), Self.note(2)], request: 1))
    #expect(outputs.isEmpty)
  }

  @Test func aFullPageAsksForTheNextAfterItsLastSeq() {
    let notes = (1...M.pageSize).map { Self.note($0) }
    var (state, _) = M.transition(.idle, .refreshed)
    let outputs: [M.Output]
    (state, outputs) = M.transition(
      state, .pageLoaded(M.Page(notes: notes, count: M.pageSize), request: 1))
    #expect(outputs == [.loadPage(after: M.pageSize, request: 2)])
    #expect(state == .loading(notes: notes, request: 2))
  }

  @Test func refreshingAsksAfterTheLastNoteHeld() {
    let state = M.State.loaded(notes: [Self.note(1), Self.note(5)], request: 1)
    let (next, outputs) = M.transition(state, .refreshed)
    #expect(outputs == [.loadPage(after: 5, request: 2)])
    #expect(next.notes.count == 2)
  }

  @Test func notesStayInOrderAndRepeatsAreIgnored() {
    let merged = M.merge([Self.note(3), Self.note(1)], [Self.note(2), Self.note(3, author: "x")])
    #expect(merged.map(\.seq) == [1, 2, 3])
    #expect(merged.last?.authorID == "me")
  }

  @Test func aFailureKeepsWhatIsHeldAndRefreshRetries() {
    let state = M.State.loading(notes: [Self.note(1)], request: 4)
    let (failed, _) = M.transition(state, .failed(.unavailable, request: 4))
    #expect(failed == .failed(notes: [Self.note(1)], .unavailable, request: 4))
    let (retry, outputs) = M.transition(failed, .refreshed)
    #expect(outputs == [.loadPage(after: 1, request: 5)])
    #expect(retry.notes == [Self.note(1)])
  }

  @Test func aStaleAnswerChangesNothing() {
    let state = M.State.loading(notes: [], request: 3)
    #expect(
      M.transition(state, .pageLoaded(M.Page(notes: [Self.note(1)], count: 1), request: 2)).0
        == state)
    #expect(M.transition(state, .failed(.unavailable, request: 1)).0 == state)
  }

  @Test(arguments: [
    (TransportError.api(.unauthorized), HistoryFailure.signedOut),
    (.api(.notFound), .notPaired),
    (.api(.unavailable), .unavailable),
    (.network("x"), .unavailable),
  ])
  func failuresMap(error: TransportError, failure: HistoryFailure) {
    #expect(HistoryFailure(error) == failure)
  }

  @Test func eachFailureHasItsOwnWords() {
    let all: [HistoryFailure] = [.signedOut, .notPaired, .unavailable]
    #expect(Set(all.map(\.message)).count == all.count)
  }
}

@Suite @MainActor struct HistoryModelTests {
  nonisolated static let compact = CompactStrokes(strokes: [
    CompactStroke(color: "#A5442B", width: 30, points: [10, 10, 200, 200])
  ])

  nonisolated static func entry(_ seq: Int, author: String) -> NoteEntry {
    NoteEntry(
      seq: seq,
      note: .drawing(
        id: NoteId("n\(seq)"), author: UserId(author), sentAt: seq * 1000, compact: compact,
        image: MediaKey("k\(seq)")))
  }

  @Test func notesAppearInOrderWithDirections() async {
    var api = APIClient.offline
    api.listNotes = { (_) async throws(TransportError) in
      ListNotesResponse(notes: [
        Self.entry(1, author: "me"), Self.entry(2, author: "them"),
        NoteEntry(
          seq: 3,
          note: .photo(
            id: NoteId("p"), author: UserId("them"), sentAt: 3000, image: MediaKey("img"))),
      ])
    }
    let model = HistoryModel(api: api, me: "me")
    model.refresh()
    await model.settled()
    #expect(model.records.map(\.direction) == [.received, .sent])
    #expect(model.records.map(\.date.timeIntervalSince1970) == [2, 1])
    #expect(model.hiddenCount == 1)
    #expect(model.failure == nil)
  }

  @Test func noNotesIsAnEmptyList() async {
    var api = APIClient.offline
    api.listNotes = { (_) async throws(TransportError) in ListNotesResponse(notes: []) }
    let model = HistoryModel(api: api, me: "me")
    model.refresh()
    await model.settled()
    #expect(model.records.isEmpty)
    #expect(model.failure == nil)
  }

  @Test func anUnpairedAccountSaysSo() async {
    var api = APIClient.offline
    api.listNotes = { (_) async throws(TransportError) in throw .api(.notFound) }
    let model = HistoryModel(api: api, me: "me")
    model.refresh()
    await model.settled()
    #expect(model.failure == .notPaired)
  }

  @Test func idsAreStablePerSeq() {
    #expect(HistoryModel.id(forSeq: 5) == HistoryModel.id(forSeq: 5))
    #expect(HistoryModel.id(forSeq: 5) != HistoryModel.id(forSeq: 6))
  }

  @Test func theStreakReadsAsDays() {
    #expect(StreakBadge.text(days: 1) == "1 day in a row")
    #expect(StreakBadge.text(days: 12) == "12 days in a row")
  }
}
