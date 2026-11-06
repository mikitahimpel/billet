import Foundation
import Testing
import Transport
import Wire
@testable import Billet

nonisolated private let me = UserId("user-me")
nonisolated private let partner = UserId("user-partner")
nonisolated private let words = RiddleWords(easy: ["cat"], medium: ["rainbow"], hard: ["birthday"])

/// The pair's room as the model sees it: one open riddle per drawer, tries that count, the word hidden from the
/// guesser until the round ends, and Mochi's hints as the server gives them.
private nonisolated final class FakeRiddleRoom: @unchecked Sendable {
    var riddles: [Riddle] = []
    var words: [RiddleId: String] = [:]
    var series = 0
    var best = 0
    var offline = false
    /// What the next hint gives: the decoys taken away first, then the letters it shows.
    var nextRemoved: [Int] = []
    var nextReveals: [RevealedLetter] = []

    /// A riddle from `drawer` for `word`, with `tiles` (the word's letters and decoys).
    @discardableResult
    func add(_ word: String, by drawer: UserId, tiles: [String], at: Int = 1) -> Riddle {
        let riddle = Riddle(id: .make(), drawer: drawer, shape: word.split(separator: " ").map(\.count), tiles: tiles,
                            word: drawer == me ? word : nil, compact: CompactStrokes(strokes: []),
                            image: MediaKey("media-1"), at: at)
        riddles.append(riddle)
        words[riddle.id] = word
        return riddle
    }

    func update(_ id: RiddleId, _ change: (Riddle) -> Riddle) -> Riddle {
        let index = riddles.firstIndex { $0.id == id }!
        riddles[index] = change(riddles[index])
        return riddles[index]
    }

    static func with(_ riddle: Riddle, revealed: [RevealedLetter]? = nil, removed: [Int]? = nil, hints: Int? = nil,
                     tries: Int? = nil, state: RiddleState? = nil, word: String? = nil) -> Riddle {
        Riddle(id: riddle.id, drawer: riddle.drawer, shape: riddle.shape, tiles: riddle.tiles,
               revealed: revealed ?? riddle.revealed, removed: removed ?? riddle.removed, hints: hints ?? riddle.hints,
               tries: tries ?? riddle.tries, state: state ?? riddle.state, word: word ?? riddle.word,
               compact: riddle.compact, image: riddle.image, at: riddle.at)
    }

    var view: RiddlesResponse {
        RiddlesResponse(open: riddles.filter { $0.state == .open }, ended: riddles.filter { $0.state != .open },
                        series: series, best: best)
    }

    var sync: DrawGuessSync {
        DrawGuessSync(
            fetch: { () throws(TransportError) in
                if self.offline { throw .network("offline") }
                return self.view
            },
            upload: { _ throws(TransportError) in
                if self.offline { throw .network("offline") }
                return MediaKey("media-2")
            },
            send: { request throws(TransportError) in
                if self.offline { throw .network("offline") }
                if self.riddles.contains(where: { $0.drawer == me && $0.state == .open }) { throw .api(.invalidRequest) }
                return self.add(request.word, by: me, tiles: request.word.replacingOccurrences(of: " ", with: "")
                    .map(String.init))
            },
            guess: { id, _, guess throws(TransportError) in
                if self.offline { throw .network("offline") }
                let right = guess == self.words[id]
                let riddle = self.update(id) { riddle in
                    FakeRiddleRoom.with(riddle, tries: riddle.tries + 1, state: right ? .solved(at: 5) : nil,
                              word: right ? self.words[id] : nil)
                }
                if right { self.series += 1 }
                return GuessRiddleResponse(riddle: riddle, right: right)
            },
            hint: { id throws(TransportError) in
                if self.offline { throw .network("offline") }
                return self.update(id) { riddle in
                    if riddle.hints == 0 { return FakeRiddleRoom.with(riddle, removed: self.nextRemoved, hints: 1) }
                    let letter = self.nextReveals.removeFirst()
                    return FakeRiddleRoom.with(riddle, revealed: riddle.revealed + [letter], hints: riddle.hints + 1)
                }
            },
            giveUp: { id throws(TransportError) in
                if self.offline { throw .network("offline") }
                self.series = 0
                return self.update(id) { FakeRiddleRoom.with($0, state: .givenUp(at: 5), word: self.words[id]) }
            })
    }
}

/// "cat" among nine decoys: c is tile 1, a tile 3, t tile 6.
nonisolated private let catTiles = ["x", "c", "q", "a", "z", "m", "t", "p", "r", "o", "b", "k"]

struct DrawGuessTests {
    @Test func derivesEachPhase() async {
        #expect(DrawGuessModel(sync: nil, viewer: nil, words: words).phase == .unpaired)

        let unreachable = FakeRiddleRoom()
        unreachable.offline = true
        let offline = DrawGuessModel(sync: unreachable.sync, viewer: me, words: words)
        #expect(offline.phase == .loading)
        await offline.load()
        #expect(offline.phase == .offline)
        unreachable.offline = false
        await offline.load()
        #expect(offline.phase == .draw)

        let room = FakeRiddleRoom()
        room.add("cat", by: partner, tiles: catTiles)
        room.add("dog", by: me, tiles: catTiles)
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        // Guessing comes before waiting on one's own riddle.
        #expect(model.phase == .guess)

        let mine = FakeRiddleRoom()
        mine.add("dog", by: me, tiles: catTiles)
        let waiting = DrawGuessModel(sync: mine.sync, viewer: me, words: words)
        await waiting.load()
        #expect(waiting.phase == .waiting)
    }

    @Test func placesTilesAndTakesThemBack() async {
        let room = FakeRiddleRoom()
        room.add("cat", by: partner, tiles: catTiles)
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        #expect(model.tiles.count == 12)
        #expect(model.slots.map(\.kind) == [.empty, .empty, .empty])

        await model.place(1)
        await model.place(3)
        #expect(model.attempt == "ca")
        #expect(!model.tiles.contains { $0.index == 1 })
        #expect(model.tiles.count == 10)

        model.takeBack(0)
        #expect(model.slots[0].kind == .empty)
        #expect(model.tiles.contains { $0.index == 1 })
        // The next tile fills the first empty blank.
        await model.place(6)
        #expect(model.slots[0].letter == "t")
        #expect(room.riddles[0].tries == 0)
    }

    @Test func aWrongGuessClearsThePlacedTilesButKeepsTheRevealedLetters() async {
        let room = FakeRiddleRoom()
        let riddle = room.add("cat", by: partner, tiles: catTiles)
        _ = room.update(riddle.id) { FakeRiddleRoom.with($0, revealed: [RevealedLetter(index: 0, letter: "c")], hints: 2) }
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        #expect(model.slots[0].kind == .revealed)
        // The c tile stands in for the revealed letter.
        #expect(!model.tiles.contains { $0.index == 1 })

        await model.place(0)
        await model.place(2)
        #expect(room.riddles[0].tries == 1)
        #expect(model.misses == 1)
        #expect(model.placed.isEmpty)
        #expect(model.slots.map(\.kind) == [.revealed, .empty, .empty])
        #expect(model.phase == .guess)
    }

    @Test func aRightGuessEndsTheRound() async {
        let room = FakeRiddleRoom()
        room.add("cat", by: partner, tiles: catTiles)
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        for tile in [1, 3, 6] { await model.place(tile) }
        #expect(model.phase == .ended)
        #expect(model.finished?.word == "cat")
        #expect(model.finished.map(DrawGuessModel.endedTitle) == "Solved on try 1 🎉")
        #expect(model.series == 1)
        model.drawNext()
        #expect(model.phase == .draw)
        #expect(DrawGuessModel.status(model.phase, partner: "Leo", letters: 0, lastEnded: model.lastEnded,
                                      endedMine: false) == "Solved! Your turn to draw")
    }

    @Test func givingUpEndsTheRoundAndShowsTheWord() async {
        let room = FakeRiddleRoom()
        room.add("cat", by: partner, tiles: catTiles)
        room.series = 3
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        await model.giveUp()
        #expect(model.phase == .ended)
        #expect(model.finished?.word == "cat")
        #expect(model.series == 0)
    }

    @Test func appliesTheHintsRemovedTilesAndRevealedLetters() async {
        let room = FakeRiddleRoom()
        room.add("cat", by: partner, tiles: catTiles)
        room.nextRemoved = [0, 2, 4, 5]
        room.nextReveals = [RevealedLetter(index: 2, letter: "t"), RevealedLetter(index: 0, letter: "c")]
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        await model.place(1)

        await model.hint()
        #expect(model.tiles.map(\.index) == [1, 3, 6, 7, 8, 9, 10, 11])
        #expect(model.placed.isEmpty)
        #expect(model.canHint)

        await model.hint()
        #expect(model.slots.map(\.kind) == [.empty, .empty, .revealed])
        #expect(model.slots[2].letter == "t")
        #expect(!model.tiles.contains { $0.index == 6 })
        #expect(model.canHint)

        // Hints show all letters but one at most: two of three is the last.
        await model.hint()
        #expect(model.slots.map(\.kind) == [.revealed, .empty, .revealed])
        #expect(!model.canHint)
    }

    @Test func followsTheSocketAndDropsStaleFrames() async {
        let room = FakeRiddleRoom()
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        #expect(model.phase == .draw)

        let riddle = room.add("cat", by: partner, tiles: catTiles)
        model.changed(riddle)
        #expect(model.phase == .guess)

        model.changed(FakeRiddleRoom.with(riddle, tries: 2))
        model.changed(FakeRiddleRoom.with(riddle, tries: 1))
        #expect(model.theirs?.tries == 2)

        // A guess on the other phone solved it.
        model.changed(FakeRiddleRoom.with(riddle, tries: 3, state: .solved(at: 9), word: "cat"))
        #expect(model.phase == .ended)
        model.changed(FakeRiddleRoom.with(riddle, tries: 2))
        #expect(model.theirs == nil)
        #expect(model.lastEnded?.word == "cat")

        // A read that left before the solve can't open it again.
        await model.load()
        #expect(model.theirs == nil)
        #expect(model.phase == .ended)
    }

    @Test func sendsARiddleAndWaits() async {
        let room = FakeRiddleRoom()
        let model = DrawGuessModel(sync: room.sync, viewer: me, words: words)
        await model.load()
        #expect(model.offers == ["cat", "rainbow", "birthday"])

        room.offline = true
        #expect(await !model.send(word: " Our Dacha ", png: Data(), compact: CompactStrokes(strokes: [])))
        #expect(model.unsent)
        room.offline = false
        #expect(await model.send(word: "our dacha", png: Data(), compact: CompactStrokes(strokes: [])))
        #expect(model.phase == .waiting)
        #expect(model.mine?.word == "our dacha")
        #expect(await !model.send(word: "cat1", png: Data(), compact: CompactStrokes(strokes: [])))
    }

    @Test func checksTheOwnWordAsTheRoomDoes() {
        #expect(DrawGuessModel.riddleWord("  Cat ") == "cat")
        #expect(DrawGuessModel.riddleWord("Our Dacha") == "our dacha")
        #expect(DrawGuessModel.riddleWord("abcdef ghijkl") == "abcdef ghijkl")
        #expect(DrawGuessModel.riddleWord("abcdefghijklm") == nil)
        #expect(DrawGuessModel.riddleWord("two  spaces") == nil)
        #expect(DrawGuessModel.riddleWord("cat1") == nil)
        #expect(DrawGuessModel.riddleWord("café") == nil)
        #expect(DrawGuessModel.riddleWord("   ") == nil)
    }

    @Test func paysAsTheRoomDoes() {
        let open = Riddle(id: .make(), drawer: partner, shape: [3], tiles: catTiles, compact: CompactStrokes(strokes: []),
                          image: MediaKey("media-1"), at: 1)
        #expect(DrawGuessModel.coinsLine(open) == nil)
        #expect(DrawGuessModel.coinsLine(FakeRiddleRoom.with(open, state: .solved(at: 2))) == "+10 coins")
        #expect(DrawGuessModel.coinsLine(FakeRiddleRoom.with(open, hints: 2, state: .solved(at: 2))) == "+6 coins")
        #expect(DrawGuessModel.coinsLine(FakeRiddleRoom.with(open, hints: 5, state: .solved(at: 2))) == "+4 coins")
        #expect(DrawGuessModel.coinsLine(FakeRiddleRoom.with(open, hints: 2, state: .givenUp(at: 2))) == "+3 coins")
    }

    @Test func wordsTheCard() {
        let solved = Riddle(id: .make(), drawer: me, shape: [3], tiles: catTiles, state: .solved(at: 2), word: "cat",
                            compact: CompactStrokes(strokes: []), image: MediaKey("media-1"), at: 1)
        #expect(DrawGuessModel.status(.draw, partner: "Leo", letters: 0, lastEnded: nil, endedMine: false)
            == "Draw a riddle for Leo")
        #expect(DrawGuessModel.status(.guess, partner: "Leo", letters: 4, lastEnded: nil, endedMine: false)
            == "Leo drew you a riddle · 4 letters")
        #expect(DrawGuessModel.status(.waiting, partner: "Leo", letters: 0, lastEnded: nil, endedMine: false)
            == "Waiting for Leo to guess")
        #expect(DrawGuessModel.status(.draw, partner: "Leo", letters: 0, lastEnded: solved, endedMine: true)
            == "Leo solved it")
        #expect(DrawGuessModel.status(.unpaired, partner: "Leo", letters: 0, lastEnded: nil, endedMine: false)
            == "Pair up to play")
        #expect(DrawGuessModel.seriesLine(3) == "3 solved in a row")
    }

    @Test func replaysThePointsInDrawingOrder() {
        let strokes = [
            Stroke(color: "#000000", width: 0.1, points: [Point(x: 0, y: 0), Point(x: 1, y: 0)]),
            Stroke(color: "#000000", width: 0.1, points: [Point(x: 0, y: 1), Point(x: 1, y: 1), Point(x: 1, y: 2)]),
        ]
        #expect(DrawGuessModel.prefix(strokes, points: 0).isEmpty)
        #expect(DrawGuessModel.prefix(strokes, points: 3).map(\.points.count) == [2, 1])
        #expect(DrawGuessModel.prefix(strokes, points: 99).map(\.points.count) == [2, 3])
        let fitted = DrawGuessModel.fitted(strokes).flatMap(\.points)
        #expect(fitted.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    /// The bundled words are the server's catalog: a drift would offer words the server list doesn't know.
    @Test func bundlesTheServersWords() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../packages/contracts/domain/src/riddle-words.ts").standardizedFileURL
        let source = try String(contentsOf: url, encoding: .utf8)
        func tier(_ name: String) throws -> [String] {
            let section = try #require(source.firstMatch(of: try Regex("\(name): words\\(\\[([\\s\\S]*?)\\]\\),")))
            let body = try #require(section.output[1].substring)
            let pairs = try Regex(#"\["([a-z ]+)", ""#)
            return body.matches(of: pairs).compactMap { $0.output[1].substring.map(String.init) }
        }
        let bundled = RiddleWords.bundled
        #expect(bundled.easy == (try tier("easy")))
        #expect(bundled.medium == (try tier("medium")))
        #expect(bundled.hard == (try tier("hard")))
        #expect(bundled.easy.count > 100)
    }
}
