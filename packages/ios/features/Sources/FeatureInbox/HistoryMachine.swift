import BilletKit
import Foundation
import Ink
import Transport
import Wire

/// One note of the couple's history, in the form the screen needs.
public struct HistoryNote: Equatable, Sendable {
  public enum Content: Equatable, Sendable {
    case drawing([Stroke])
    /// A photo, a text note, or a drawing whose strokes could not be read. The list does not show
    /// these yet.
    case other
  }

  /// The note's place in the history, which orders it.
  public let seq: Int
  public let authorID: String
  public let sentAt: Date
  public let content: Content

  public init(seq: Int, authorID: String, sentAt: Date, content: Content) {
    self.seq = seq
    self.authorID = authorID
    self.sentAt = sentAt
    self.content = content
  }
}

public enum HistoryFailure: Equatable, Sendable {
  case signedOut
  /// The account has no partner yet, so there is no history.
  case notPaired
  case unavailable

  public init(_ error: TransportError) {
    switch error {
    case .api(.unauthorized): self = .signedOut
    case .api(.notFound): self = .notPaired
    case .api(.invalidRequest), .api(.unavailable), .api(.invalidInvite), .api(.alreadyPaired),
      .api(.invalidPurchase), .api(.inkNotOwned),
      .api(.appleIdInUse), .network, .status, .maintenance, .encoding, .decoding:
      self = .unavailable
    }
  }
}

/// Loads the history a page at a time until it reaches the end, and again from where it stopped
/// whenever it is refreshed.
///
/// Pages arrive oldest first and each starts after the last `seq` held, so `notes` stays in order
/// and a refresh adds only what is new. A page's notes are merged by `seq`, so a repeated one
/// changes nothing.
public enum HistoryMachine: Machine {
  /// The server's page size. A shorter page is the last one.
  public static let pageSize = 100

  public struct Page: Equatable, Sendable {
    public var notes: [HistoryNote]
    /// How many entries the server sent, whatever could be shown.
    public var count: Int

    public init(notes: [HistoryNote], count: Int) {
      self.notes = notes
      self.count = count
    }
  }

  public enum State: Equatable, Sendable {
    case idle
    case loading(notes: [HistoryNote], request: Int)
    case loaded(notes: [HistoryNote], request: Int)
    case failed(notes: [HistoryNote], HistoryFailure, request: Int)

    public var notes: [HistoryNote] {
      switch self {
      case .idle: []
      case .loading(let notes, _), .loaded(let notes, _), .failed(let notes, _, _): notes
      }
    }

    var request: Int {
      switch self {
      case .idle: 0
      case .loading(_, let request), .loaded(_, let request), .failed(_, _, let request): request
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case refreshed
    case pageLoaded(Page, request: Int)
    case failed(HistoryFailure, request: Int)

    var answeredRequest: Int? {
      switch self {
      case .refreshed: nil
      case .pageLoaded(_, let request), .failed(_, let request): request
      }
    }
  }

  public enum Output: Equatable, Sendable {
    case loadPage(after: Int?, request: Int)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    if let answered = event.answeredRequest, answered != state.request {
      return (state, [])
    }
    let request = state.request + 1
    switch (state, event) {
    case (.idle, .refreshed), (.loaded, .refreshed), (.failed, .refreshed):
      let notes = state.notes
      return (
        .loading(notes: notes, request: request),
        [.loadPage(after: notes.last?.seq, request: request)]
      )

    case (.loading(let notes, _), .pageLoaded(let page, _)):
      let merged = merge(notes, page.notes)
      if page.count >= pageSize, let last = merged.last {
        return (
          .loading(notes: merged, request: request),
          [.loadPage(after: last.seq, request: request)]
        )
      }
      return (.loaded(notes: merged, request: state.request), [])

    case (.loading(let notes, _), .failed(let failure, _)):
      return (.failed(notes: notes, failure, request: state.request), [])

    case (.loading, .refreshed),
      (.idle, .pageLoaded), (.idle, .failed),
      (.loaded, .pageLoaded), (.loaded, .failed),
      (.failed, .pageLoaded), (.failed, .failed):
      return (state, [])
    }
  }

  /// `existing` and `new` by `seq`, oldest first, keeping the first copy of a repeated `seq`.
  static func merge(_ existing: [HistoryNote], _ new: [HistoryNote]) -> [HistoryNote] {
    var seen = Set(existing.map(\.seq))
    var result = existing
    for note in new where seen.insert(note.seq).inserted {
      result.append(note)
    }
    return result.sorted { $0.seq < $1.seq }
  }
}

extension HistoryMachine {
  public static func run(_ output: Output, api: APIClient) async -> Event? {
    switch output {
    case .loadPage(let after, let request):
      do {
        let response = try await api.listNotes(after)
        let notes = response.notes.map { note(from: $0) }
        return .pageLoaded(Page(notes: notes, count: response.notes.count), request: request)
      } catch {
        return .failed(HistoryFailure(error), request: request)
      }
    }
  }

  static func note(from entry: NoteEntry) -> HistoryNote {
    switch entry.note {
    case .drawing(_, let author, let sentAt, let compact, _, _):
      let strokes = try? InkDecoder.decode(compact)
      return HistoryNote(
        seq: entry.seq, authorID: author.rawValue, sentAt: date(sentAt),
        content: strokes.map(HistoryNote.Content.drawing) ?? .other)
    case .photo(_, let author, let sentAt, _, _, _, _, _):
      return HistoryNote(
        seq: entry.seq, authorID: author.rawValue, sentAt: date(sentAt), content: .other)
    // The Nooki notes screen shows text notes; this list keeps to drawings.
    case .text(_, let author, let sentAt, _, _, _):
      return HistoryNote(
        seq: entry.seq, authorID: author.rawValue, sentAt: date(sentAt), content: .other)
    }
  }

  private static func date(_ milliseconds: Int) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1000)
  }
}
