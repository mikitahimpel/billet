import FeatureGames
import Foundation
import Ink
import Observation
import Transport
import Wire

/// Draw & guess: one partner draws a word, the other builds it from letter tiles while the drawing replays;
/// each has at most one open riddle. The store around `DrawGuessMachine` (FeatureGames) with the word offers.
@Observable
final class DrawGuessModel {
    enum Phase: Equatable {
        case loading, guess, waiting, draw, ended, unpaired, offline
    }

    typealias Slot = DrawGuessMachine.Slot
    typealias Tile = DrawGuessMachine.Tile

    /// What a round pays the guesser (`solveReward` and `giveUpReward` on the server).
    nonisolated static let solveCoins = 3
    nonisolated static let hintCost = 1
    nonisolated static let solveFloor = 1
    nonisolated static let giveUpCoins = 1
    nonisolated static let maxLetters = 12
    nonisolated static let maxLength = 24

    /// One word of each tier to offer the drawer.
    private(set) var offers: [String] = []

    @ObservationIgnored private let store: DrawGuessStore
    @ObservationIgnored private let words: RiddleWords

    /// Without `sync` or `viewer` the account has no partner and the game is `unpaired`.
    init(sync: DrawGuessSync?, viewer: UserId?, words: RiddleWords) {
        store = .drawGuess(sync, viewer: viewer)
        self.words = words
        offers = words.offers()
    }

    private var game: DrawGuessMachine.Game? {
        if case .playing(let game) = store.state { game } else { nil }
    }

    private var guess: DrawGuessMachine.Guess? {
        if case .guessing(let guess) = game?.turn { guess } else { nil }
    }

    var phase: Phase {
        switch store.state {
        case .unpaired: .unpaired
        case .unread: .loading
        case .unreachable: .offline
        case .playing(let game):
            switch game.turn {
            case .guessing: .guess
            case .waiting: .waiting
            case .ended: .ended
            case .drawing: .draw
            }
        }
    }

    /// For this user to guess.
    var theirs: Riddle? { game?.theirs }
    var mine: Riddle? { game?.mine }
    /// Of either partner.
    var lastEnded: Riddle? { game?.board.ended.first }
    var series: Int { game?.board.series ?? 0 }
    var best: Int { game?.board.best ?? 0 }
    /// The riddle this user was guessing that ended here, shown until they move on to drawing.
    var finished: Riddle? {
        if case .ended(let riddle) = game?.turn { riddle } else { nil }
    }
    /// Counts wrong tries, so the screen shakes the tiles once for each.
    var misses: Int { game?.misses ?? 0 }
    /// Letter slot (spaces not counted) to the tile placed in it.
    var placed: [Int: Int] { guess?.placed ?? [:] }
    /// A try, hint or give-up is on its way; the tiles and hints wait for it.
    var busy: Bool { guess?.isBusy ?? false }
    var sending: Bool {
        if case .drawing(.sending) = game?.turn { true } else { false }
    }
    /// The last try, hint, give-up or send on the screen shown now didn't reach the room.
    var unsent: Bool {
        switch game?.turn {
        case .guessing(let guess): guess.step == .notSent
        case .drawing(.notSent): true
        case .drawing(.idle), .drawing(.sending), .waiting, .ended, nil: false
        }
    }

    func isMine(_ riddle: Riddle) -> Bool { riddle.drawer == game?.viewer }

    // MARK: Reading

    func load() async {
        store.send(.loadAsked)
        await store.until { [self] in !isReading }
    }

    private var isReading: Bool {
        switch store.state {
        case .unpaired: false
        case .unread(_, let read), .unreachable(_, let read): read.isReading
        case .playing(let game): game.read.isReading
        }
    }

    func changed(_ riddle: Riddle) {
        store.send(.changed(riddle))
    }

    // MARK: Guessing

    /// Revealed ones filled in.
    var slots: [Slot] {
        theirs.map { DrawGuessMachine.slots($0, placed: placed) } ?? []
    }

    /// The tiles still to pick from: not taken away by the first hint, not placed, and not standing in for a letter a
    /// later hint revealed.
    var tiles: [Tile] {
        theirs.map { DrawGuessMachine.tiles($0, placed: placed) } ?? []
    }

    /// Whether Mochi has a hint left: the first takes away decoys, each later one shows a letter, up to all but one.
    var canHint: Bool { theirs.map(DrawGuessMachine.canHint) ?? false }

    /// With the riddle's spaces.
    var attempt: String {
        theirs.map { DrawGuessMachine.attempt($0, slots: slots) } ?? ""
    }

    /// Once every slot is filled, sends the word as a try.
    func place(_ index: Int) async {
        await act(.tilePlaced(index, key: .make()))
    }

    func takeBack(_ slot: Int) {
        store.send(.tileTakenBack(slot: slot))
    }

    func hint() async {
        await act(.hintTapped)
    }

    func giveUp() async {
        await act(.giveUpTapped)
    }

    /// Leaves the ended round for the word picker.
    func drawNext() {
        offers = words.offers()
        store.send(.drawNextTapped)
    }

    func shuffleOffers() {
        offers = words.offers()
    }

    // MARK: Drawing

    /// Sends `word` with its drawing: the PNG to the media store first, then the riddle. A retry of the same word
    /// keeps the riddle's id.
    @discardableResult
    func send(word: String, png: Data, compact: CompactStrokes) async -> Bool {
        guard let word = Self.riddleWord(word) else { return false }
        await act(.sendTapped(word: word, png: png, compact: compact, id: .make()))
        return mine?.word == word
    }

    /// Sends `event` and, if it started a request, waits for its answer.
    private func act(_ event: DrawGuessMachine.Event) async {
        let before = store.state
        store.send(event)
        guard store.state != before else { return }
        await store.until { [self] in !busy && !sending }
    }

    // MARK: Rules

    /// `text` as the room keeps a word (trimmed, lowercased), or nil when it can't be one: a to z with single spaces,
    /// at most 12 letters and 24 characters (`RiddleWord` on the server).
    nonisolated static func riddleWord(_ text: String) -> String? {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, word.count <= maxLength else { return nil }
        let parts = word.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("a"..."z").contains($0) } }) else { return nil }
        return parts.reduce(0) { $0 + $1.count } <= maxLetters ? word : nil
    }

    /// What an ended round paid the guesser; nil while it is open.
    nonisolated static func coins(_ riddle: Riddle) -> Int? {
        switch riddle.state {
        case .open: nil
        case .solved: max(solveFloor, solveCoins - hintCost * riddle.hints)
        case .givenUp: giveUpCoins
        }
    }

    nonisolated static func coinsLine(_ riddle: Riddle) -> String? {
        coins(riddle).map { "+\($0) \($0 == 1 ? "coin" : "coins")" }
    }

    nonisolated static func endedTitle(_ riddle: Riddle) -> String {
        switch riddle.state {
        case .open: "Still open"
        case .solved: "Solved on try \(riddle.tries) 🎉"
        case .givenUp: "Gave up"
        }
    }

    nonisolated static func seriesLine(_ series: Int) -> String {
        "\(series) solved in a row"
    }

    /// The Us tab card's line. `letters` counts the partner's open riddle's letters; `lastEnded` is the newest round
    /// that ended and `endedMine` whether this user drew it.
    nonisolated static func status(_ phase: Phase, partner: String, letters: Int, lastEnded: Riddle?,
                                   endedMine: Bool) -> String {
        switch phase {
        case .loading: "Draw a word, guess a word"
        case .guess: "\(partner) drew you a riddle · \(letters) \(letters == 1 ? "letter" : "letters")"
        case .waiting: "Waiting for \(partner) to guess"
        case .ended, .draw:
            switch lastEnded?.state {
            case .solved?: endedMine ? "\(partner) solved it" : "Solved! Your turn to draw"
            case .givenUp?, .open?, nil: "Draw a riddle for \(partner)"
            }
        case .unpaired: "Pair up to play"
        case .offline: "Offline · try again soon"
        }
    }

    // MARK: Replay

    /// `strokes` moved and scaled so their bounds fill a unit square with a margin: the drawer's canvas was a whole
    /// screen, the replay is a square card.
    nonisolated static func fitted(_ strokes: [Stroke], margin: Double = 0.08) -> [Stroke] {
        let points = strokes.flatMap(\.points)
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return strokes }
        let pad = strokes.map(\.width).max() ?? 0
        let span = max(maxX - minX, maxY - minY) + pad
        guard span > 0 else { return strokes }
        let scale = (1 - 2 * margin) / span
        let offsetX = margin + ((1 - 2 * margin) - (maxX - minX) * scale) / 2
        let offsetY = margin + ((1 - 2 * margin) - (maxY - minY) * scale) / 2
        return strokes.map { stroke in
            Stroke(color: stroke.color, width: stroke.width * scale, points: stroke.points.map {
                Point(x: ($0.x - minX) * scale + offsetX, y: ($0.y - minY) * scale + offsetY)
            })
        }
    }

    /// The first `count` points of `strokes` in drawing order, for a replay at an even pace.
    nonisolated static func prefix(_ strokes: [Stroke], points count: Int) -> [Stroke] {
        var left = count
        var shown: [Stroke] = []
        for stroke in strokes {
            guard left > 0 else { break }
            shown.append(Stroke(color: stroke.color, width: stroke.width, points: Array(stroke.points.prefix(left))))
            left -= stroke.points.count
        }
        return shown
    }
}

/// The words a drawer is offered, by tier: the English words of `packages/contracts/domain/src/riddle-words.ts`,
/// bundled as `RiddleWords.json`.
struct RiddleWords: Codable, Equatable {
    var easy: [String]
    var medium: [String]
    var hard: [String]

    static var bundled: RiddleWords {
        guard let url = Bundle.main.url(forResource: "RiddleWords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let words = try? JSONDecoder().decode(RiddleWords.self, from: data) else {
            return RiddleWords(easy: ["cat"], medium: ["rainbow"], hard: ["birthday"])
        }
        return words
    }

    /// Easy first.
    func offers() -> [String] {
        [easy, medium, hard].compactMap { $0.randomElement() }
    }
}
