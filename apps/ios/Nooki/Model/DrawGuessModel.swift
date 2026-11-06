import Foundation
import Ink
import Observation
import Transport
import Wire

/// Draw & guess as this user plays it. One partner draws a word, the other builds it from letter tiles while the
/// drawing replays; each has at most one open riddle at a time. The room sends each change over its socket too.
@Observable
final class DrawGuessModel {
    enum Phase: Equatable {
        case loading, guess, waiting, draw, ended, unpaired, offline
    }

    /// What a round pays the guesser (`solveReward` and `giveUpReward` on the server).
    nonisolated static let solveCoins = 10
    nonisolated static let hintCost = 2
    nonisolated static let solveFloor = 4
    nonisolated static let giveUpCoins = 3
    nonisolated static let maxLetters = 12
    nonisolated static let maxLength = 24

    /// The pair's riddles as the room last answered them, with later changes from the socket and this phone merged in.
    private(set) var response: RiddlesResponse?
    /// The room wasn't reachable on the last read.
    private(set) var offline = false
    /// The last try, hint or send didn't reach the room.
    private(set) var unsent = false
    private(set) var sending = false
    /// The riddle this user was guessing that ended here, shown until they move on to drawing.
    private(set) var finished: Riddle?
    /// Letter slot (spaces not counted) to the tile placed in it.
    private(set) var placed: [Int: Int] = [:]
    /// Counts wrong tries, so the screen shakes the tiles once for each.
    private(set) var misses = 0
    /// One word of each tier to offer the drawer.
    private(set) var offers: [String] = []

    @ObservationIgnored private let sync: DrawGuessSync?
    @ObservationIgnored private let viewer: UserId?
    @ObservationIgnored private let words: RiddleWords
    /// The id of the riddle being sent, kept for a retry of the same word so the room stores it once.
    @ObservationIgnored private var draft: (word: String, id: RiddleId)?
    /// The key of a try that didn't reach the room, reused when the same guess is sent again.
    @ObservationIgnored private var unsentTry: (guess: String, key: IdempotencyKey)?

    /// Without `sync` or `viewer` the account has no partner and the game is `unpaired`.
    init(sync: DrawGuessSync?, viewer: UserId?, words: RiddleWords) {
        self.sync = sync
        self.viewer = viewer
        self.words = words
        offers = words.offers()
    }

    var phase: Phase {
        guard sync != nil, viewer != nil else { return .unpaired }
        guard response != nil else { return offline ? .offline : .loading }
        if finished != nil { return .ended }
        if theirs != nil { return .guess }
        if mine != nil { return .waiting }
        return .draw
    }

    /// The partner's open riddle, for this user to guess.
    var theirs: Riddle? { response?.open.first { $0.drawer != viewer } }
    /// This user's own open riddle, waiting for the partner.
    var mine: Riddle? { response?.open.first { $0.drawer == viewer } }
    /// The newest riddle that ended, of either partner.
    var lastEnded: Riddle? { response?.ended.first }
    var series: Int { response?.series ?? 0 }
    var best: Int { response?.best ?? 0 }

    func isMine(_ riddle: Riddle) -> Bool { riddle.drawer == viewer }

    // MARK: Reading

    func load() async {
        guard let sync else { return }
        do throws(TransportError) {
            merge(try await sync.fetch())
            offline = false
        } catch {
            offline = true
        }
    }

    /// A riddle as the room's socket sent it.
    func changed(_ riddle: Riddle) {
        apply(riddle)
    }

    // MARK: Guessing

    /// The letter slots of the open riddle, revealed ones filled in.
    var slots: [Slot] {
        guard let riddle = theirs else { return [] }
        let letters = riddle.shape.reduce(0, +)
        let revealed = Dictionary(riddle.revealed.map { ($0.index, $0.letter) }, uniquingKeysWith: { first, _ in first })
        return (0..<letters).map { index in
            if let letter = revealed[index] { return Slot(index: index, letter: letter, kind: .revealed) }
            if let tile = placed[index], riddle.tiles.indices.contains(tile) {
                return Slot(index: index, letter: riddle.tiles[tile], kind: .placed(tile: tile))
            }
            return Slot(index: index, letter: nil, kind: .empty)
        }
    }

    /// The tiles still to pick from: not taken away by the first hint, not placed, and not standing in for a letter a
    /// later hint revealed.
    var tiles: [Tile] {
        guard let riddle = theirs else { return [] }
        let used = Set(placed.values).union(Self.spent(riddle))
        return riddle.tiles.enumerated().compactMap { index, letter in
            used.contains(index) ? nil : Tile(index: index, letter: letter)
        }
    }

    /// Whether Mochi has a hint left: the first takes away decoys, each later one shows a letter, up to all but one.
    var canHint: Bool {
        guard let riddle = theirs else { return false }
        return riddle.hints == 0 || riddle.revealed.count < riddle.shape.reduce(0, +) - 1
    }

    /// Puts tile `index` in the first empty slot. Once every slot is filled, sends the word as a try.
    func place(_ index: Int) async {
        guard tiles.contains(where: { $0.index == index }),
              let slot = slots.first(where: { $0.kind == .empty }) else { return }
        placed[slot.index] = index
        if !slots.contains(where: { $0.kind == .empty }) { await submit() }
    }

    /// Takes the tile in `slot` back to the tiles.
    func takeBack(_ slot: Int) {
        placed[slot] = nil
    }

    /// The word in the slots, with the riddle's spaces.
    var attempt: String {
        guard let riddle = theirs else { return "" }
        let letters = slots.map { $0.letter ?? "" }
        var words: [String] = []
        var start = 0
        for length in riddle.shape {
            words.append(letters[start..<min(start + length, letters.count)].joined())
            start += length
        }
        return words.joined(separator: " ")
    }

    @discardableResult
    func submit() async -> Bool {
        guard let sync, let riddle = theirs, !slots.contains(where: { $0.kind == .empty }) else { return false }
        let guess = attempt
        let key = unsentTry.flatMap { $0.guess == guess ? $0.key : nil } ?? IdempotencyKey.make()
        unsent = false
        do throws(TransportError) {
            let answer = try await sync.guess(riddle.id, key, guess)
            unsentTry = nil
            if !answer.right {
                placed = [:]
                misses += 1
            }
            apply(answer.riddle)
            return answer.right
        } catch {
            if case .api = error {
                // The round ended meanwhile, on the other phone or by the drawer's side: the room's view is the truth.
                unsentTry = nil
                placed = [:]
                await load()
            } else {
                unsentTry = (guess, key)
                unsent = true
            }
            return false
        }
    }

    func hint() async {
        guard let sync, let riddle = theirs, canHint else { return }
        unsent = false
        do throws(TransportError) {
            let hinted = try await sync.hint(riddle.id)
            // The hint can take a placed tile away or fill its slot, so the guess starts again.
            placed = [:]
            apply(hinted)
        } catch {
            if case .api = error { await load() } else { unsent = true }
        }
    }

    func giveUp() async {
        guard let sync, let riddle = theirs else { return }
        unsent = false
        do throws(TransportError) {
            apply(try await sync.giveUp(riddle.id))
        } catch {
            if case .api = error { await load() } else { unsent = true }
        }
    }

    /// Leaves the ended round for the word picker.
    func drawNext() {
        finished = nil
        offers = words.offers()
    }

    func shuffleOffers() {
        offers = words.offers()
    }

    // MARK: Drawing

    /// Sends `word` with its drawing: the PNG to the media store first, then the riddle. A retry of the same word
    /// keeps the riddle's id.
    @discardableResult
    func send(word: String, png: Data, compact: CompactStrokes) async -> Bool {
        guard let sync, let word = Self.riddleWord(word), !sending else { return false }
        let id = draft.flatMap { $0.word == word ? $0.id : nil } ?? RiddleId.make()
        draft = (word, id)
        sending = true
        unsent = false
        defer { sending = false }
        do throws(TransportError) {
            let image = try await sync.upload(png)
            apply(try await sync.send(SendRiddleRequest(id: id, word: word, compact: compact, image: image)))
            draft = nil
            return true
        } catch {
            if case .api = error {
                // A riddle of this user's is still open, or the word wasn't one: the room's view says which.
                draft = nil
                await load()
            } else {
                unsent = true
            }
            return false
        }
    }

    // MARK: Merging

    /// How far a riddle's round has come. Nothing in a round goes back, so a lower one is older news.
    private static func progress(_ riddle: Riddle) -> [Int] {
        [riddle.state == .open ? 0 : 1, riddle.tries, riddle.hints, riddle.revealed.count]
    }

    private static func newer(_ old: Riddle?, _ next: Riddle) -> Riddle {
        guard let old else { return next }
        return progress(next).lexicographicallyPrecedes(progress(old)) ? old : next
    }

    private var all: [Riddle] { (response?.open ?? []) + (response?.ended ?? []) }

    private static func endedAt(_ riddle: Riddle) -> Int {
        switch riddle.state {
        case .open: riddle.at
        case .solved(let at), .givenUp(let at): at
        }
    }

    /// Takes the room's whole view, keeping anything newer this phone already has: a read that left before a try or a
    /// socket frame can't undo it.
    private func merge(_ next: RiddlesResponse) {
        var known = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for riddle in next.open + next.ended { known[riddle.id] = Self.newer(known[riddle.id], riddle) }
        rebuild(known.values, series: next.series, best: next.best)
    }

    private func apply(_ riddle: Riddle) {
        let old = all.first { $0.id == riddle.id }
        let next = Self.newer(old, riddle)
        var series = response?.series ?? 0
        var best = response?.best ?? 0
        if old?.state == .open, next.state != .open {
            // The socket and the answers carry no series; the next read brings the room's.
            switch next.state {
            case .solved:
                series += 1
                best = max(best, series)
            case .givenUp: series = 0
            case .open: break
            }
            if next.drawer != viewer { finished = next }
        }
        var known = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        known[next.id] = next
        rebuild(known.values, series: series, best: best)
    }

    private func rebuild(_ riddles: some Collection<Riddle>, series: Int, best: Int) {
        // One open riddle per drawer: a newer one from the same drawer means the older ended unseen.
        var open: [UserId: Riddle] = [:]
        for riddle in riddles where riddle.state == .open {
            if let other = open[riddle.drawer], other.at >= riddle.at { continue }
            open[riddle.drawer] = riddle
        }
        let ended = riddles.filter { $0.state != .open }.sorted { Self.endedAt($0) > Self.endedAt($1) }
        response = RiddlesResponse(open: open.values.sorted { $0.at < $1.at }, ended: Array(ended.prefix(20)),
                                   series: series, best: best)
    }

    // MARK: Rules

    /// The tiles that stand in for revealed letters: for each, the first tile of that letter the hint didn't take away.
    nonisolated static func spent(_ riddle: Riddle) -> Set<Int> {
        var spent = Set(riddle.removed)
        for letter in riddle.revealed {
            if let tile = riddle.tiles.indices.first(where: { riddle.tiles[$0] == letter.letter && !spent.contains($0) }) {
                spent.insert(tile)
            }
        }
        return spent
    }

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
        coins(riddle).map { "+\($0) coins" }
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

    struct Slot: Equatable {
        enum Kind: Equatable { case empty, revealed, placed(tile: Int) }

        let index: Int
        let letter: String?
        let kind: Kind
    }

    struct Tile: Equatable, Identifiable {
        let index: Int
        let letter: String

        var id: Int { index }
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

    /// One random word of each tier, easy first.
    func offers() -> [String] {
        [easy, medium, hard].compactMap { $0.randomElement() }
    }
}
