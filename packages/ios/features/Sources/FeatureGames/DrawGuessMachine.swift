import BilletKit
import Foundation
import Transport
import Wire

/// Draw & guess: one partner draws a word, the other builds it from tiles; one open riddle each.
/// The socket can move a riddle on at any moment, so this phone's work on a riddle lives in its
/// `Turn` and can't outlive it.
public enum DrawGuessMachine: Machine {

  /// Why the room didn't take a request.
  public enum Failure: Error, Equatable, Sendable {
    /// The network or the server: the same request may go again.
    case unreachable
    /// The room said no: the round ended meanwhile, a riddle of this user's is still open, or the
    /// word wasn't one. Its own view is the truth, so it is read again.
    case refused

    public init(_ error: TransportError) {
      switch error {
      case .api: self = .refused
      case .network, .status, .maintenance, .encoding, .decoding: self = .unreachable
      }
    }
  }

  public typealias Read = GameRead

  /// One try at the partner's word. `key` is repeated when the same word goes again, so the room
  /// counts it once.
  public struct Try: Equatable, Sendable {
    public let guess: String
    public let key: IdempotencyKey
  }

  /// This user guessing the partner's open riddle `riddle`.
  public struct Guess: Equatable, Sendable {
    public let riddle: RiddleId
    /// Letter slot (spaces not counted) to the tile placed in it.
    public var placed: [Int: Int] = [:]
    public var step: Step = .picking
    /// The last try that didn't reach the room, sent again with its key if the word is the same.
    public var retry: Try?

    public init(riddle: RiddleId) {
      self.riddle = riddle
    }

    public enum Step: Equatable, Sendable {
      case picking
      /// The last try, hint or give-up didn't reach the room; picking goes on.
      case notSent
      /// The tiles and hints wait for the answer, so a second tap can't spend another hint or a
      /// late answer clear tiles placed after it.
      case trying(Try)
      case hinting
      case givingUp
    }

    public var isBusy: Bool {
      switch step {
      case .picking, .notSent: false
      case .trying, .hinting, .givingUp: true
      }
    }
  }

  /// A riddle of this user's on its way. `id` is kept for a retry of the same word, so the room
  /// stores it once.
  public struct Draft: Equatable, Sendable {
    public let id: RiddleId
    public let word: String
  }

  public enum Send: Equatable, Sendable {
    case idle
    case sending(Draft)
    /// The last send didn't reach the room.
    case notSent(Draft)
  }

  public enum Turn: Equatable, Sendable {
    case guessing(Guess)
    /// This user's own riddle is open, waiting for the partner.
    case waiting
    /// The riddle this user was guessing ended here, shown until they move on to drawing.
    case ended(Riddle)
    /// Nothing to guess or wait on: the word picker and the canvas.
    case drawing(Send)
  }

  public struct Game: Equatable, Sendable {
    public let viewer: UserId
    /// The room's last view, with later changes from the socket and this phone merged in.
    public var board: RiddlesResponse
    public var turn: Turn
    /// Wrong tries here, so the screen shakes the tiles once for each.
    public var misses = 0
    public var read: Read

    /// The partner's open riddle, for this user to guess.
    public var theirs: Riddle? { board.open.first { $0.drawer != viewer } }
    /// This user's own open riddle, waiting for the partner.
    public var mine: Riddle? { board.open.first { $0.drawer == viewer } }
  }

  public enum State: Equatable, Sendable {
    /// No partner or no account: nothing to read or play.
    case unpaired
    /// Nothing known from the room yet.
    case unread(UserId, Read)
    /// The last read didn't reach the room, and nothing is known from it.
    case unreachable(UserId, Read)
    case playing(Game)

    public static func initial(viewer: UserId?) -> State {
      viewer.map { .unread($0, .idle(last: 0)) } ?? .unpaired
    }
  }

  public enum Event: Equatable, Sendable {
    // From the shell
    case loadAsked
    /// A riddle as the room's socket sent it.
    case changed(Riddle)
    // From the screen
    /// `key` is the try's, used when the tile fills the last slot.
    case tilePlaced(Int, key: IdempotencyKey)
    case tileTakenBack(slot: Int)
    case hintTapped
    case giveUpTapped
    case drawNextTapped
    /// `word` as the room keeps it; `id` is used unless a send of the same word didn't reach it.
    case sendTapped(word: String, png: Data, compact: CompactStrokes, id: RiddleId)
    // Results
    case read(RiddlesResponse, request: Int)
    case readFailed(request: Int)
    case guessed(RiddleId, GuessRiddleResponse)
    case guessFailed(RiddleId, Failure)
    case hinted(Riddle)
    case hintFailed(RiddleId, Failure)
    case gaveUp(Riddle)
    case giveUpFailed(RiddleId, Failure)
    case sent(Riddle)
    case sendFailed(RiddleId, Failure)
  }

  /// A riddle to send: the PNG to the media store first, then the riddle that names it.
  public struct Upload: Equatable, Sendable {
    public let id: RiddleId
    public let word: String
    public let png: Data
    public let compact: CompactStrokes
  }

  public enum Output: Equatable, Sendable {
    case read(request: Int)
    case guess(RiddleId, key: IdempotencyKey, guess: String)
    case hint(RiddleId)
    case giveUp(RiddleId)
    case send(Upload)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch state {
    case .unpaired:
      switch event {
      case .loadAsked, .changed, .tilePlaced, .tileTakenBack, .hintTapped, .giveUpTapped,
        .drawNextTapped, .sendTapped, .read, .readFailed, .guessed, .guessFailed, .hinted,
        .hintFailed, .gaveUp, .giveUpFailed, .sent, .sendFailed:
        return (state, [])
      }

    case .unread(let viewer, let read), .unreachable(let viewer, let read):
      switch event {
      case .loadAsked:
        guard let (next, request) = read.next() else { return (state, []) }
        return (state.with(read: next), [.read(request: request)])
      case .read(let response, let request):
        guard read.isReading else { return (state, []) }
        var game = Game(
          viewer: viewer, board: RiddlesResponse(), turn: .drawing(.idle),
          read: read.answered(request))
        game.merge(response)
        return (.playing(game), [])
      case .readFailed(let request):
        guard read.isReading, read.answered(request) != read else { return (state, []) }
        return (.unreachable(viewer, read.answered(request)), [])
      case .changed(let riddle):
        var game = Game(viewer: viewer, board: RiddlesResponse(), turn: .drawing(.idle), read: read)
        game.apply(riddle)
        return (.playing(game), [])
      case .tilePlaced, .tileTakenBack, .hintTapped, .giveUpTapped, .drawNextTapped, .sendTapped,
        .guessed, .guessFailed, .hinted, .hintFailed, .gaveUp, .giveUpFailed, .sent, .sendFailed:
        return (state, [])
      }

    case .playing(var game):
      switch event {
      case .loadAsked:
        guard let (next, request) = game.read.next() else { return (state, []) }
        game.read = next
        return (.playing(game), [.read(request: request)])
      case .read(let response, let request):
        game.read = game.read.answered(request)
        game.merge(response)
        return (.playing(game), [])
      case .readFailed(let request):
        game.read = game.read.answered(request)
        return (.playing(game), [])
      case .changed(let riddle):
        game.apply(riddle)
        return (.playing(game), [])

      case .tilePlaced(let tile, let key):
        guard case .guessing(var guess) = game.turn, !guess.isBusy,
          let riddle = game.theirs, riddle.id == guess.riddle,
          tiles(riddle, placed: guess.placed).contains(where: { $0.index == tile }),
          let slot = slots(riddle, placed: guess.placed).first(where: { $0.kind == .empty })
        else { return (state, []) }
        guess.placed[slot.index] = tile
        let filled = slots(riddle, placed: guess.placed)
        guard !filled.contains(where: { $0.kind == .empty }) else {
          game.turn = .guessing(guess)
          return (.playing(game), [])
        }
        let word = attempt(riddle, slots: filled)
        let again = guess.retry.flatMap { $0.guess == word ? $0.key : nil }
        let attempt = Try(guess: word, key: again ?? key)
        guess.step = .trying(attempt)
        game.turn = .guessing(guess)
        return (.playing(game), [.guess(riddle.id, key: attempt.key, guess: attempt.guess)])
      case .tileTakenBack(let slot):
        guard case .guessing(var guess) = game.turn, !guess.isBusy, guess.placed[slot] != nil
        else { return (state, []) }
        guess.placed[slot] = nil
        game.turn = .guessing(guess)
        return (.playing(game), [])
      case .hintTapped:
        guard case .guessing(var guess) = game.turn, !guess.isBusy,
          let riddle = game.theirs, riddle.id == guess.riddle, canHint(riddle)
        else { return (state, []) }
        guess.step = .hinting
        game.turn = .guessing(guess)
        return (.playing(game), [.hint(riddle.id)])
      case .giveUpTapped:
        guard case .guessing(var guess) = game.turn, !guess.isBusy else { return (state, []) }
        guess.step = .givingUp
        game.turn = .guessing(guess)
        return (.playing(game), [.giveUp(guess.riddle)])

      case .guessed(let id, let answer):
        if case .guessing(var guess) = game.turn, guess.riddle == id, case .trying = guess.step {
          guess.retry = nil
          guess.step = .picking
          if !answer.right {
            guess.placed = [:]
            game.misses += 1
          }
          game.turn = .guessing(guess)
        }
        game.apply(answer.riddle)
        return (.playing(game), [])
      case .guessFailed(let id, let failure):
        if case .guessing(var guess) = game.turn, guess.riddle == id,
          case .trying(let attempt) = guess.step
        {
          switch failure {
          case .unreachable:
            guess.retry = attempt
            guess.step = .notSent
          case .refused:
            guess.retry = nil
            guess.placed = [:]
            guess.step = .picking
          }
          game.turn = .guessing(guess)
        }
        return game.reread(after: failure)
      case .hinted(let riddle):
        if case .guessing(var guess) = game.turn, guess.riddle == riddle.id, guess.step == .hinting
        {
          // The hint can take a placed tile away or fill its slot, so the guess starts again.
          guess.placed = [:]
          guess.step = .picking
          game.turn = .guessing(guess)
        }
        game.apply(riddle)
        return (.playing(game), [])
      case .gaveUp(let riddle):
        if case .guessing(var guess) = game.turn, guess.riddle == riddle.id,
          guess.step == .givingUp
        {
          guess.step = .picking
          game.turn = .guessing(guess)
        }
        game.apply(riddle)
        return (.playing(game), [])
      case .hintFailed(let id, let failure), .giveUpFailed(let id, let failure):
        if case .guessing(var guess) = game.turn, guess.riddle == id,
          guess.step == .hinting || guess.step == .givingUp
        {
          guess.step = failure == .unreachable ? .notSent : .picking
          game.turn = .guessing(guess)
        }
        return game.reread(after: failure)

      case .drawNextTapped:
        guard case .ended = game.turn else { return (state, []) }
        game.turn = .drawing(.idle)
        game.settle()
        return (.playing(game), [])
      case .sendTapped(let word, let png, let compact, let id):
        guard case .drawing(let send) = game.turn else { return (state, []) }
        let draft: Draft
        switch send {
        case .idle: draft = Draft(id: id, word: word)
        case .sending: return (state, [])
        case .notSent(let last): draft = Draft(id: last.word == word ? last.id : id, word: word)
        }
        game.turn = .drawing(.sending(draft))
        return (
          .playing(game),
          [.send(Upload(id: draft.id, word: word, png: png, compact: compact))]
        )
      case .sent(let riddle):
        game.apply(riddle)
        return (.playing(game), [])
      case .sendFailed(let id, let failure):
        if case .drawing(.sending(let draft)) = game.turn, draft.id == id {
          game.turn = .drawing(failure == .unreachable ? .notSent(draft) : .idle)
        }
        return game.reread(after: failure)
      }
    }
  }

  // MARK: Merging

  /// How far a riddle's round has come. Nothing in a round goes back, so a lower one is older news.
  private static func progress(_ riddle: Riddle) -> [Int] {
    [riddle.state == .open ? 0 : 1, riddle.tries, riddle.hints, riddle.revealed.count]
  }

  static func newer(_ old: Riddle?, _ next: Riddle) -> Riddle {
    guard let old else { return next }
    return progress(next).lexicographicallyPrecedes(progress(old)) ? old : next
  }

  static func endedAt(_ riddle: Riddle) -> Int {
    switch riddle.state {
    case .open: riddle.at
    case .solved(let at), .givenUp(let at): at
    }
  }

  // MARK: Guessing

  public struct Slot: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
      case empty
      case revealed
      case placed(tile: Int)
    }

    public let index: Int
    public let letter: String?
    public let kind: Kind
  }

  public struct Tile: Equatable, Identifiable, Sendable {
    public let index: Int
    public let letter: String

    public var id: Int { index }
  }

  /// The letter slots of `riddle`, revealed ones filled in.
  public static func slots(_ riddle: Riddle, placed: [Int: Int]) -> [Slot] {
    let letters = riddle.shape.reduce(0, +)
    let revealed = Dictionary(
      riddle.revealed.map { ($0.index, $0.letter) }, uniquingKeysWith: { first, _ in first })
    return (0..<letters).map { index in
      if let letter = revealed[index] {
        return Slot(index: index, letter: letter, kind: .revealed)
      }
      if let tile = placed[index], riddle.tiles.indices.contains(tile) {
        return Slot(index: index, letter: riddle.tiles[tile], kind: .placed(tile: tile))
      }
      return Slot(index: index, letter: nil, kind: .empty)
    }
  }

  /// The tiles still to pick from: not taken away by the first hint, not placed, and not standing
  /// in for a letter a later hint revealed.
  public static func tiles(_ riddle: Riddle, placed: [Int: Int]) -> [Tile] {
    let used = Set(placed.values).union(spent(riddle))
    return riddle.tiles.enumerated().compactMap { index, letter in
      used.contains(index) ? nil : Tile(index: index, letter: letter)
    }
  }

  /// The word in the slots, with the riddle's spaces.
  public static func attempt(_ riddle: Riddle, slots: [Slot]) -> String {
    let letters = slots.map { $0.letter ?? "" }
    var words: [String] = []
    var start = 0
    for length in riddle.shape {
      words.append(letters[start..<min(start + length, letters.count)].joined())
      start += length
    }
    return words.joined(separator: " ")
  }

  /// Whether Mochi has a hint left: the first takes away decoys, each later one shows a letter, up
  /// to all but one.
  public static func canHint(_ riddle: Riddle) -> Bool {
    riddle.hints == 0 || riddle.revealed.count < riddle.shape.reduce(0, +) - 1
  }

  /// The tiles that stand in for revealed letters: for each, the first tile of that letter the hint
  /// didn't take away.
  public static func spent(_ riddle: Riddle) -> Set<Int> {
    var spent = Set(riddle.removed)
    for letter in riddle.revealed {
      if let tile = riddle.tiles.indices.first(where: {
        riddle.tiles[$0] == letter.letter && !spent.contains($0)
      }) {
        spent.insert(tile)
      }
    }
    return spent
  }
}

extension DrawGuessMachine.State {
  fileprivate func with(read: DrawGuessMachine.Read) -> Self {
    switch self {
    case .unread(let viewer, _): .unread(viewer, read)
    case .unreachable(let viewer, _): .unreachable(viewer, read)
    case .unpaired, .playing: self
    }
  }
}

extension DrawGuessMachine.Game {
  typealias M = DrawGuessMachine

  private var all: [Riddle] { board.open + board.ended }

  /// Takes the room's whole view, keeping anything newer this phone already has: a read that left
  /// before a try or a socket frame can't undo it.
  mutating func merge(_ next: RiddlesResponse) {
    var known = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for riddle in next.open + next.ended { known[riddle.id] = M.newer(known[riddle.id], riddle) }
    rebuild(known.values, series: next.series, best: next.best)
    settle()
  }

  mutating func apply(_ riddle: Riddle) {
    let old = all.first { $0.id == riddle.id }
    let next = M.newer(old, riddle)
    var series = board.series
    var best = board.best
    var ended: Riddle?
    if old?.state == .open, next.state != .open {
      // The socket and the answers carry no series; the next read brings the room's.
      switch next.state {
      case .solved:
        series += 1
        best = max(best, series)
      case .givenUp: series = 0
      case .open: break
      }
      if next.drawer != viewer { ended = next }
    }
    var known = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    known[next.id] = next
    rebuild(known.values, series: series, best: best)
    if let ended { turn = .ended(ended) }
    settle()
  }

  /// Moves the turn to what the board holds: the partner's riddle first, then this user's own, then
  /// drawing. An ended round stays until it is put away; the turn for a riddle stays while it is
  /// open, and starts empty for a new one.
  mutating func settle() {
    switch turn {
    case .ended: return
    case .guessing(let guess) where guess.riddle == theirs?.id: return
    case .guessing, .waiting, .drawing: break
    }
    if let theirs {
      turn = .guessing(M.Guess(riddle: theirs.id))
    } else if mine != nil {
      turn = .waiting
    } else if case .drawing = turn {
      return
    } else {
      turn = .drawing(.idle)
    }
  }

  /// After a refusal the room's own view is the truth, so it is read again.
  func reread(after failure: M.Failure) -> (M.State, [M.Output]) {
    var game = self
    guard failure == .refused, let (next, request) = game.read.next() else {
      return (.playing(game), [])
    }
    game.read = next
    return (.playing(game), [.read(request: request)])
  }

  private mutating func rebuild(_ riddles: some Collection<Riddle>, series: Int, best: Int) {
    // One open riddle per drawer: a newer one from the same drawer means the older ended unseen.
    var open: [UserId: Riddle] = [:]
    for riddle in riddles where riddle.state == .open {
      if let other = open[riddle.drawer], other.at >= riddle.at { continue }
      open[riddle.drawer] = riddle
    }
    let ended = riddles.filter { $0.state != .open }.sorted { M.endedAt($0) > M.endedAt($1) }
    board = RiddlesResponse(
      open: open.values.sorted { $0.at < $1.at }, ended: Array(ended.prefix(20)), series: series,
      best: best)
  }
}
