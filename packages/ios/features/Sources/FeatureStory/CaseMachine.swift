import BilletKit
import Foundation
import StoryInterface

/// The case file of one episode: what a partner sees and does with it. Every change goes through `transition`;
/// the server only ever hears about a look or a name, and answers with both partners' marks.
public enum CaseMachine: Machine {
  /// Everything the screens read: the episode, which side this phone is, both partners' marks, and the moment they
  /// were read at, which the day-by-day pace needs.
  public struct Book: Equatable, Sendable {
    public var episode: Episode
    public var side: Side
    public var mine: [CaseMark]
    public var partner: [CaseMark]
    public var now: Date
    public var calendar: Calendar

    public init(
      episode: Episode, side: Side, mine: [CaseMark] = [], partner: [CaseMark] = [],
      now: Date, calendar: Calendar = .current
    ) {
      self.episode = episode
      self.side = side
      self.mine = mine
      self.partner = partner
      self.now = now
      self.calendar = calendar
    }

    public var progress: CaseProgress {
      CaseProgress(episode: episode, mine: mine, partner: partner, now: now, calendar: calendar)
    }

    func read(_ marks: Marks, at now: Date) -> Book {
      var next = self
      next.mine = marks.mine
      next.partner = marks.partner
      next.now = now
      return next
    }
  }

  public struct Marks: Equatable, Sendable {
    public var mine: [CaseMark]
    public var partner: [CaseMark]

    public init(mine: [CaseMark], partner: [CaseMark]) {
      self.mine = mine
      self.partner = partner
    }
  }

  /// A write in flight, for the screen that made it.
  public enum Sending: Equatable, Sendable {
    case idle
    case sending
    /// The room did not answer. Nothing was lost: doing it again sends it again.
    case failed
  }

  public enum State: Equatable, Sendable {
    /// No case: the flag is off, there is no partner or there is no episode.
    case unavailable
    /// The episode is picked and the room has not been read yet. The case cannot be opened.
    case loading(Episode, Side)
    case closed(Book)
    /// The case sheet is open on the file: the beats so far.
    case file(Book)
    case clue(Book, beat: Int, Sending)
    case naming(Book, choice: String?, Sending)
    case ending(Book, Sending)

    public var book: Book? {
      switch self {
      case .unavailable, .loading: nil
      case .closed(let book), .file(let book), .clue(let book, _, _), .naming(let book, _, _),
        .ending(let book, _):
        book
      }
    }

    public var isOpen: Bool {
      switch self {
      case .unavailable, .loading, .closed: false
      case .file, .clue, .naming, .ending: true
      }
    }
  }

  public enum Event: Equatable, Sendable {
    case enabled(Episode, Side)
    case disabled
    /// The pair's marks, read from the room.
    case fetched(Marks, at: Date)
    /// Something may have changed: the app came forward, or the partner did something.
    case refresh
    case opened
    case dismissed
    case back
    case lookCloser(beat: Int)
    /// The player looks at the clue on the screen.
    case found
    case nameSuspect
    case choose(String)
    case confirmName
    case watchEnding
    /// The room took a write and answered with the pair's marks.
    case marked(Marks, at: Date)
    case markFailed
  }

  public enum Output: Equatable, Sendable {
    case fetch
    case mark(episode: String, kind: CaseMark.Kind, ref: String)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch (state, event) {
    case (.unavailable, .enabled(let episode, let side)):
      return (.loading(episode, side), [.fetch])
    case (.unavailable, .disabled), (.unavailable, .fetched), (.unavailable, .refresh),
      (.unavailable, .opened), (.unavailable, .dismissed), (.unavailable, .back),
      (.unavailable, .lookCloser), (.unavailable, .found), (.unavailable, .nameSuspect),
      (.unavailable, .choose), (.unavailable, .confirmName), (.unavailable, .watchEnding),
      (.unavailable, .marked), (.unavailable, .markFailed):
      return (state, [])

    case (.loading, .disabled), (.closed, .disabled), (.file, .disabled), (.clue, .disabled),
      (.naming, .disabled), (.ending, .disabled):
      return (.unavailable, [])
    case (.loading, .enabled), (.closed, .enabled), (.file, .enabled), (.clue, .enabled),
      (.naming, .enabled), (.ending, .enabled):
      return (state, [])

    case (.loading(let episode, let side), .fetched(let marks, let now)):
      return (.closed(Book(episode: episode, side: side, now: now).read(marks, at: now)), [])
    case (.loading, .refresh):
      return (state, [.fetch])
    case (.loading, .opened), (.loading, .dismissed), (.loading, .back), (.loading, .lookCloser),
      (.loading, .found), (.loading, .nameSuspect), (.loading, .choose), (.loading, .confirmName),
      (.loading, .watchEnding), (.loading, .marked), (.loading, .markFailed):
      return (state, [])

    case (.closed(let book), .fetched(let marks, let now)):
      return (.closed(book.read(marks, at: now)), [])
    case (.file(let book), .fetched(let marks, let now)):
      return (.file(book.read(marks, at: now)), [])
    case (.clue(let book, let beat, let sending), .fetched(let marks, let now)):
      return (.clue(book.read(marks, at: now), beat: beat, sending), [])
    case (.naming(let book, let choice, let sending), .fetched(let marks, let now)):
      return (.naming(book.read(marks, at: now), choice: choice, sending), [])
    case (.ending(let book, let sending), .fetched(let marks, let now)):
      return (.ending(book.read(marks, at: now), sending), [])

    case (.closed, .refresh), (.file, .refresh), (.clue, .refresh), (.naming, .refresh),
      (.ending, .refresh):
      return (state, [.fetch])

    case (.closed(let book), .opened):
      return (.file(book), [])
    case (.file, .opened), (.clue, .opened), (.naming, .opened), (.ending, .opened):
      return (state, [])

    case (.closed, .dismissed):
      return (state, [])
    case (.file(let book), .dismissed), (.clue(let book, _, _), .dismissed),
      (.naming(let book, _, _), .dismissed), (.ending(let book, _), .dismissed):
      return (.closed(book), [])

    case (.clue(let book, _, _), .back), (.naming(let book, _, _), .back),
      (.ending(let book, _), .back):
      return (.file(book), [])
    case (.closed, .back), (.file, .back):
      return (state, [])

    case (.file(let book), .lookCloser(let beat)):
      guard book.progress.beats.indices.contains(beat), book.progress.beats[beat] != .notYet else {
        return (state, [])
      }
      return (.clue(book, beat: beat, .idle), [])
    case (.closed, .lookCloser), (.clue, .lookCloser), (.naming, .lookCloser),
      (.ending, .lookCloser):
      return (state, [])

    case (.clue(let book, let beat, let sending), .found):
      guard sending != .sending, book.progress.beats[beat].isWaiting else { return (state, []) }
      return (
        .clue(book, beat: beat, .sending),
        [.mark(episode: book.episode.id, kind: .found, ref: book.episode.beats[beat].id)]
      )
    case (.closed, .found), (.file, .found), (.naming, .found), (.ending, .found):
      return (state, [])

    case (.file(let book), .nameSuspect):
      switch book.progress.stage {
      case .naming: return (.naming(book, choice: nil, .idle), [])
      case .clues, .named, .readyToTell, .told: return (state, [])
      }
    case (.closed, .nameSuspect), (.clue, .nameSuspect), (.naming, .nameSuspect),
      (.ending, .nameSuspect):
      return (state, [])

    case (.naming(let book, _, let sending), .choose(let id)):
      guard sending != .sending, book.episode.suspect(id) != nil else { return (state, []) }
      return (.naming(book, choice: id, .idle), [])
    case (.closed, .choose), (.file, .choose), (.clue, .choose), (.ending, .choose):
      return (state, [])

    case (.naming(let book, let choice?, let sending), .confirmName):
      guard sending != .sending, book.progress.stage == .naming else { return (state, []) }
      return (
        .naming(book, choice: choice, .sending),
        [.mark(episode: book.episode.id, kind: .named, ref: choice)]
      )
    case (.naming(_, nil, _), .confirmName), (.closed, .confirmName), (.file, .confirmName),
      (.clue, .confirmName), (.ending, .confirmName):
      return (state, [])

    case (.file(let book), .watchEnding):
      switch book.progress.stage {
      case .readyToTell:
        return (
          .ending(book, .sending),
          [.mark(episode: book.episode.id, kind: .found, ref: Episode.endingRef)]
        )
      case .told: return (.ending(book, .idle), [])
      case .clues, .naming, .named: return (state, [])
      }
    case (.closed, .watchEnding), (.clue, .watchEnding), (.naming, .watchEnding),
      (.ending, .watchEnding):
      return (state, [])

    case (.clue(let book, let beat, _), .marked(let marks, let now)):
      return (.clue(book.read(marks, at: now), beat: beat, .idle), [])
    case (.naming(let book, let choice, _), .marked(let marks, let now)):
      let next = book.read(marks, at: now)
      switch next.progress.stage {
      case .named, .readyToTell, .told: return (.file(next), [])
      case .clues, .naming: return (.naming(next, choice: choice, .idle), [])
      }
    case (.ending(let book, _), .marked(let marks, let now)):
      return (.ending(book.read(marks, at: now), .idle), [])
    case (.file(let book), .marked(let marks, let now)):
      return (.file(book.read(marks, at: now)), [])
    case (.closed(let book), .marked(let marks, let now)):
      return (.closed(book.read(marks, at: now)), [])

    case (.clue(let book, let beat, _), .markFailed):
      return (.clue(book, beat: beat, .failed), [])
    case (.naming(let book, let choice, _), .markFailed):
      return (.naming(book, choice: choice, .failed), [])
    case (.ending(let book, _), .markFailed):
      return (.ending(book, .failed), [])
    case (.closed, .markFailed), (.file, .markFailed):
      return (state, [])
    }
  }
}
