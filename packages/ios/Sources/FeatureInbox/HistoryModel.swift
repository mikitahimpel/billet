import BilletKit
import Foundation
import Observation
import Transport

/// The couple's history for the signed-in account `me`, kept up to date from the backend.
@MainActor
@Observable
public final class HistoryModel {
  private let store: Store<HistoryMachine>
  private let me: String

  public var state: HistoryMachine.State { store.state }

  public init(api: APIClient, me: String) {
    self.me = me
    store = Store<HistoryMachine>(initial: .idle) { output in
      await HistoryMachine.run(output, api: api)
    }
  }

  public func refresh() { store.send(.refreshed) }
  public func settled() async { await store.settled() }

  /// The drawings, newest first, as the notes list shows them.
  public var records: [NoteRecord] {
    state.notes.reversed().compactMap { note in
      guard case .drawing(let strokes) = note.content else { return nil }
      return NoteRecord(
        id: Self.id(forSeq: note.seq),
        direction: note.authorID == me ? .sent : .received,
        date: note.sentAt, strokes: strokes)
    }
  }

  /// How many notes are in the history but not drawings, so the list can say it leaves them out.
  public var hiddenCount: Int {
    state.notes.count { note in
      if case .other = note.content { true } else { false }
    }
  }

  /// The `seq` of the newest note held, so a socket can ask only for what is newer.
  public var lastSeq: Int? { state.notes.last?.seq }

  public var failure: HistoryFailure? {
    if case .failed(_, let failure, _) = state { failure } else { nil }
  }

  public var isLoading: Bool {
    if case .loading = state { true } else { false }
  }

  /// A stable ID per `seq`, for the list.
  static func id(forSeq seq: Int) -> UUID {
    let hex = String(format: "%012llx", UInt64(max(seq, 0)))
    return UUID(uuidString: "00000000-0000-0000-0000-\(hex)") ?? UUID()
  }
}
