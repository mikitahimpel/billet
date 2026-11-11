import Foundation
import Ink
import Transport
import Wire
@testable import Billet

/// Who knows who and Draw & guess with fixed content, one model per phase, for the gallery. Each game's room is a
/// fake that answers every read with the same view, so a model loads straight into the phase it shows.
@MainActor
enum GameFixture {
    nonisolated static let me = UserId("gallery-me")
    nonisolated static let partner = UserId("gallery-partner")

    // MARK: Who knows who

    enum WhoKnowsScenario {
        /// The subject's first look at today's round: the host's intro.
        case intro
        case answering
        case guessing
        case waiting
        case revealed
        case offline
        case unpaired
    }

    nonisolated static let questions = [
        question(1, "What would {name} order at a new café?", "What would you order at a new café?",
                 ["Flat white", "Matcha latte", "Hot chocolate", "Whatever's quickest"], .food),
        question(2, "Where does {name} go to recharge?", "Where do you go to recharge?",
                 ["A long walk", "Bed with a series", "A loud dinner with friends", "The gym"], .habits),
        question(3, "Which trip would {name} pick?", "Which trip would you pick?",
                 ["Lisbon by the sea", "A cabin in the mountains", "Tokyo for a week", "Home, honestly"], .dreams),
        question(4, "What does {name} hum in the shower?", "What do you hum in the shower?",
                 ["Something from the radio", "A film soundtrack", "An old childhood song", "Nothing at all"], .music),
        question(5, "What would {name} save first in a fire?", "What would you save first in a fire?",
                 ["The photos", "The cat", "The laptop", "The plant"], .quirks),
    ]

    nonisolated private static func question(_ id: Int, _ guess: String, _ selfText: String, _ options: [String],
                                             _ tag: GuessTag) -> GuessQuestion {
        GuessQuestion(id: id, guess: guess, selfText: selfText, options: options, tag: tag)
    }

    static func whoKnows(_ scenario: WhoKnowsScenario) async -> WhoKnowsModel {
        let room: WhoKnowsSync
        switch scenario {
        case .unpaired:
            return WhoKnowsModel(sync: nil, viewer: nil, catalog: questions)
        case .offline:
            room = whoKnowsRoom { () throws(TransportError) in throw .network("offline") }
        case .intro:
            room = whoKnowsRoom(GuessResponse(round: round(subject: me), partnerAnswered: 2, score: score))
        case .answering:
            room = whoKnowsRoom(GuessResponse(round: round(subject: me), answers: answers([2, 0]), partnerAnswered: 3,
                                              score: score))
        case .guessing:
            room = whoKnowsRoom(GuessResponse(round: round(subject: partner), answers: answers([1]),
                                              partnerAnswered: 5, score: score))
        case .waiting:
            room = whoKnowsRoom(GuessResponse(round: round(subject: partner), answers: answers([1, 0, 3, 2, 1]),
                                              partnerAnswered: 2, score: score))
        case .revealed:
            let truths = [1, 0, 2, 2, 1], guesses = [1, 0, 3, 2, 0]
            let reveal = zip(questions, zip(truths, guesses)).map { question, pair in
                GuessReveal(question: question.id, truth: pair.0, guess: pair.1, hit: pair.0 == pair.1)
            }
            room = whoKnowsRoom(GuessResponse(round: round(subject: partner), answers: answers(guesses),
                                              partnerAnswered: 5, reveal: reveal, score: score))
        }
        let model = WhoKnowsModel(sync: room, viewer: me, catalog: questions)
        await model.load()
        return model
    }

    nonisolated private static let score = GuessScore(weekOf: "2026-11-09", week: GuessTally(mine: 31, partner: 24),
                                                      allTime: GuessTally(mine: 212, partner: 198),
                                                      bestWeek: GuessTally(mine: 44, partner: 40))

    nonisolated private static func round(subject: UserId) -> GuessRound {
        GuessRound(id: "2026-11-11", subject: subject, questions: questions.map(\.id), closesAt: 0)
    }

    nonisolated private static func answers(_ options: [Int]) -> [GuessAnswer] {
        zip(questions, options).map { GuessAnswer(question: $0.id, option: $1) }
    }

    nonisolated private static func whoKnowsRoom(_ response: GuessResponse) -> WhoKnowsSync {
        whoKnowsRoom { () throws(TransportError) in response }
    }

    nonisolated private static func whoKnowsRoom(
        _ fetch: @escaping @Sendable () async throws(TransportError) -> GuessResponse
    ) -> WhoKnowsSync {
        WhoKnowsSync(fetch: fetch, answer: { _ throws(TransportError) in try await fetch() })
    }

    // MARK: Draw & guess

    enum DrawGuessScenario {
        /// The partner's riddle with one hint taken and a letter placed.
        case guessing
        /// This user's riddle, open with the partner.
        case waiting
        case drawing
        /// The partner's riddle, solved here on the first try.
        case solved
        case offline
        case unpaired
    }

    /// One word per tier, so the drawer's offers are the same on every run.
    nonisolated static let words = RiddleWords(easy: ["moon"], medium: ["rainbow"], hard: ["lighthouse"])

    static func drawGuess(_ scenario: DrawGuessScenario) async -> DrawGuessModel {
        let room: DrawGuessSync
        switch scenario {
        case .unpaired:
            return DrawGuessModel(sync: nil, viewer: nil, words: words)
        case .offline:
            room = drawGuessRoom { () throws(TransportError) in throw .network("offline") }
        case .guessing:
            room = drawGuessRoom(RiddlesResponse(open: [rainbow(by: partner, removed: [0, 4], hints: 1)],
                                                 ended: [solvedCat], series: 3, best: 5))
        case .waiting:
            room = drawGuessRoom(RiddlesResponse(open: [rainbow(by: me)], ended: [solvedCat], series: 3, best: 5))
        case .drawing:
            room = drawGuessRoom(RiddlesResponse(ended: [solvedCat], series: 3, best: 5))
        case .solved:
            room = drawGuessRoom(RiddlesResponse(open: [rainbow(by: partner)], ended: [solvedCat], series: 3, best: 5),
                                 solves: true)
        }
        let model = DrawGuessModel(sync: room, viewer: me, words: words)
        await model.load()
        switch scenario {
        case .guessing:
            await model.place(rainbowTiles.firstIndex(of: "r") ?? 0)
        case .solved:
            var left = Array(rainbowTiles.enumerated())
            for letter in "rainbow" {
                guard let at = left.firstIndex(where: { $0.element == String(letter) }) else { continue }
                await model.place(left.remove(at: at).offset)
            }
        case .waiting, .drawing, .offline, .unpaired:
            break
        }
        return model
    }

    /// "rainbow" among five decoys.
    nonisolated private static let rainbowTiles = ["k", "a", "w", "r", "t", "i", "o", "e", "n", "b", "s", "l"]
    nonisolated private static let rainbowID = RiddleId("6F1C2A9E-4B3D-4E8A-9C1F-2D7B5A8E3C10")

    nonisolated private static func rainbow(by drawer: UserId, removed: [Int] = [], hints: Int = 0) -> Riddle {
        Riddle(id: rainbowID, drawer: drawer, shape: [7], tiles: rainbowTiles, removed: removed, hints: hints,
               word: drawer == me ? "rainbow" : nil, compact: compact(rainbowStrokes),
               image: MediaKey("gallery-rainbow"), at: 1_762_800_000_000)
    }

    nonisolated private static let solvedCat = Riddle(
        id: RiddleId("0B8D4C6A-1E2F-4A3B-8C9D-7E6F5A4B3C21"), drawer: me, shape: [3], tiles: ["c", "a", "t"], hints: 0,
        tries: 1, state: .solved(at: 1_762_700_000_000), word: "cat", compact: compact(catStrokes),
        image: MediaKey("gallery-cat"), at: 1_762_690_000_000)

    nonisolated private static func drawGuessRoom(_ response: RiddlesResponse, solves: Bool = false) -> DrawGuessSync {
        drawGuessRoom({ () throws(TransportError) in response }, solves: solves)
    }

    /// With `solves`, a try of "rainbow" solves the open riddle; any other change is refused.
    nonisolated private static func drawGuessRoom(
        _ fetch: @escaping @Sendable () async throws(TransportError) -> RiddlesResponse, solves: Bool = false
    ) -> DrawGuessSync {
        DrawGuessSync(
            fetch: fetch,
            upload: { _ throws(TransportError) in throw .api(.invalidRequest) },
            send: { _ throws(TransportError) in throw .api(.invalidRequest) },
            guess: { _, _, guess throws(TransportError) in
                guard solves, guess == "rainbow" else { throw .api(.invalidRequest) }
                let open = rainbow(by: partner)
                let solved = Riddle(id: open.id, drawer: open.drawer, shape: open.shape, tiles: open.tiles, tries: 1,
                                    state: .solved(at: 1_762_810_000_000), word: "rainbow", compact: open.compact,
                                    image: open.image, at: open.at)
                return GuessRiddleResponse(riddle: solved, right: true)
            },
            hint: { _ throws(TransportError) in throw .api(.invalidRequest) },
            giveUp: { _ throws(TransportError) in throw .api(.invalidRequest) })
    }

    // MARK: Drawings

    nonisolated private static func compact(_ strokes: [Stroke]) -> CompactStrokes {
        (try? InkEncoder.encode(strokes)) ?? CompactStrokes(strokes: [])
    }

    /// Points along a circle's arc, angles in radians, y down.
    nonisolated private static func arc(_ cx: Double, _ cy: Double, _ r: Double, from: Double, to: Double,
                                        count: Int = 32) -> [Point] {
        (0...count).map { step in
            let angle = from + (to - from) * Double(step) / Double(count)
            return Point(x: cx + r * cos(angle), y: cy + r * sin(angle))
        }
    }

    nonisolated private static let rainbowStrokes: [Stroke] = [
        ("#E8505B", 0.34), ("#F2A466", 0.28), ("#F5D76E", 0.22), ("#5AA9E6", 0.16),
    ].map { color, radius in
        Stroke(color: color, width: 0.05, points: arc(0.5, 0.62, radius, from: .pi, to: 2 * .pi))
    } + [
        Stroke(color: "#FFFFFF", width: 0.04, points: arc(0.2, 0.66, 0.07, from: .pi * 0.9, to: .pi * 2.1, count: 16)),
        Stroke(color: "#FFFFFF", width: 0.04, points: arc(0.8, 0.66, 0.07, from: .pi * 0.9, to: .pi * 2.1, count: 16)),
    ]

    nonisolated private static let catStrokes: [Stroke] = [
        Stroke(color: "#3A2A20", width: 0.035, points: arc(0.5, 0.55, 0.28, from: 0, to: 2 * .pi, count: 48)),
        Stroke(color: "#3A2A20", width: 0.035, points: [Point(x: 0.3, y: 0.36), Point(x: 0.28, y: 0.14),
                                                       Point(x: 0.44, y: 0.28)]),
        Stroke(color: "#3A2A20", width: 0.035, points: [Point(x: 0.56, y: 0.28), Point(x: 0.72, y: 0.14),
                                                       Point(x: 0.7, y: 0.36)]),
        Stroke(color: "#3A2A20", width: 0.05, points: [Point(x: 0.41, y: 0.5), Point(x: 0.41, y: 0.53)]),
        Stroke(color: "#3A2A20", width: 0.05, points: [Point(x: 0.59, y: 0.5), Point(x: 0.59, y: 0.53)]),
        Stroke(color: "#E8505B", width: 0.03, points: arc(0.5, 0.62, 0.05, from: 0.2, to: .pi - 0.2, count: 12)),
    ]
}
