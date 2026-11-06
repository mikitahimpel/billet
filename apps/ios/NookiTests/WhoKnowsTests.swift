import Foundation
import Testing
import Transport
import Wire
@testable import Billet

nonisolated private let me = UserId("user-me")
nonisolated private let partner = UserId("user-partner")

nonisolated private let questions = (1...5).map { id in
    GuessQuestion(id: id, guess: "What does {name} pick, {name}? (\(id))", selfText: "What do you pick? (\(id))",
                  options: ["A", "B", "C", "D"], tag: .quirks)
}

/// The pair's room as the model sees it: answers lock, the partner's stay hidden, and the round reveals once both
/// have answered every question.
private nonisolated final class FakeGuessRoom: @unchecked Sendable {
    var round: GuessRound
    var mine: [GuessAnswer] = []
    var theirs: [GuessAnswer] = []
    var offline = false
    var score = GuessScore(weekOf: "2026-11-02")

    init(subject: UserId) {
        round = GuessRound(id: "2026-11-06", subject: subject, questions: questions.map(\.id), closesAt: 0)
    }

    var reveal: [GuessReveal]? {
        guard mine.count == round.questions.count, theirs.count == round.questions.count else { return nil }
        let truths = round.subject == me ? mine : theirs
        let guesses = round.subject == me ? theirs : mine
        return zip(truths, guesses).map { truth, guess in
            GuessReveal(question: truth.question, truth: truth.option, guess: guess.option,
                        hit: truth.option == guess.option)
        }
    }

    var view: GuessResponse {
        GuessResponse(round: round, answers: mine, partnerAnswered: theirs.count, reveal: reveal, score: score)
    }

    var sync: WhoKnowsSync {
        WhoKnowsSync(
            fetch: { () throws(TransportError) in
                if self.offline { throw .network("offline") }
                return self.view
            },
            answer: { request throws(TransportError) in
                if self.offline { throw .network("offline") }
                if let locked = self.mine.first(where: { $0.question == request.question }) {
                    if locked.option != request.option { throw .api(.invalidRequest) }
                } else {
                    self.mine.append(GuessAnswer(question: request.question, option: request.option))
                }
                return self.view
            })
    }
}

struct WhoKnowsTests {
    @Test func derivesEachStateOfTheRound() async {
        #expect(WhoKnowsModel(sync: nil, viewer: nil, catalog: questions).phase == .unpaired)

        let offline = FakeGuessRoom(subject: me)
        offline.offline = true
        let unreachable = WhoKnowsModel(sync: offline.sync, viewer: me, catalog: questions)
        #expect(unreachable.phase == .loading)
        await unreachable.load()
        #expect(unreachable.phase == .offline)

        let about = WhoKnowsModel(sync: FakeGuessRoom(subject: me).sync, viewer: me, catalog: questions)
        await about.load()
        #expect(about.phase == .answerAboutYou)
        #expect(about.isSubject)

        let room = FakeGuessRoom(subject: partner)
        let guessing = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await guessing.load()
        #expect(guessing.phase == .guessAboutPartner)
        #expect(!guessing.isSubject)
        #expect(guessing.remaining == 5)

        for option in [0, 1, 2, 3, 0] { await guessing.answer(option) }
        #expect(guessing.phase == .waitingForPartner)
        #expect(guessing.remaining == 0)
    }

    @Test func keepsTodaysRoundWhenAnAnswerAboutAnEarlierDayArrivesLate() async {
        let room = FakeGuessRoom(subject: partner)
        let model = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await model.load()
        room.round = GuessRound(id: "2026-11-05", subject: me, questions: room.round.questions, closesAt: 0)
        await model.load()
        #expect(model.response?.round.id == "2026-11-06")
        #expect(model.phase == .guessAboutPartner)
    }

    @Test func swapsTheSubjectsNameIntoTheGuessersQuestion() {
        let question = questions[0]
        #expect(WhoKnowsModel.text(question, isSubject: false, subjectName: "Mia") == "What does Mia pick, Mia? (1)")
        #expect(WhoKnowsModel.text(question, isSubject: true, subjectName: "Mia") == "What do you pick? (1)")
    }

    @Test func locksEachAnswerAndMovesToTheNextQuestion() async {
        let room = FakeGuessRoom(subject: me)
        let model = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await model.load()
        #expect(model.current?.id == 1)

        #expect(await model.answer(2))
        #expect(model.current?.id == 2)
        #expect(room.mine == [GuessAnswer(question: 1, option: 2)])
        #expect(await !model.answer(7))
        #expect(model.current?.id == 2)
    }

    @Test func opensAnUnsentAnswerAgainAndTakesTheRoomsViewOnAConflict() async {
        let room = FakeGuessRoom(subject: me)
        let model = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await model.load()

        room.offline = true
        #expect(await !model.answer(1))
        #expect(model.unsent)
        #expect(model.current?.id == 1)
        #expect(model.answers.isEmpty)

        room.offline = false
        // Another phone of this account locked a different option meanwhile.
        room.mine = [GuessAnswer(question: 1, option: 3)]
        #expect(await !model.answer(1))
        #expect(model.answers == [GuessAnswer(question: 1, option: 3)])
        #expect(model.current?.id == 2)
    }

    @Test func followsThePartnersProgressAndAppliesTheReveal() async {
        let room = FakeGuessRoom(subject: partner)
        let model = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await model.load()
        for option in [0, 1, 2, 3, 0] { await model.answer(option) }

        model.progressed(round: room.round.id, answered: 3)
        #expect(model.partnerAnswered == 3)
        model.progressed(round: "2026-11-05", answered: 5)
        model.progressed(round: room.round.id, answered: 2)
        #expect(model.partnerAnswered == 3)

        let reveal = [
            GuessReveal(question: 1, truth: 0, guess: 0, hit: true),
            GuessReveal(question: 2, truth: 1, guess: 1, hit: true),
            GuessReveal(question: 3, truth: 3, guess: 2, hit: false),
            GuessReveal(question: 4, truth: 3, guess: 3, hit: true),
            GuessReveal(question: 5, truth: 1, guess: 0, hit: false),
        ]
        let score = GuessScore(weekOf: "2026-11-02", week: GuessTally(mine: 3, partner: 7))
        model.revealed(round: room.round.id, reveal: reveal, score: score)
        #expect(model.phase == .revealed)
        #expect(model.hits == 3)
        #expect(model.coinsEarned == 16)
        #expect(model.score == score)

        // A read that left before the reveal can't hide it again.
        room.score = GuessScore(weekOf: "2026-11-02")
        room.theirs = Array(room.mine.prefix(4))
        await model.load()
        #expect(model.phase == .revealed)
        #expect(model.score == score)
    }

    @Test func revealsInTheAnswerToTheLastAnswer() async {
        let room = FakeGuessRoom(subject: me)
        room.theirs = questions.map { GuessAnswer(question: $0.id, option: 1) }
        let model = WhoKnowsModel(sync: room.sync, viewer: me, catalog: questions)
        await model.load()
        #expect(model.partnerAnswered == 5)
        for option in [1, 1, 0, 1, 2] { await model.answer(option) }
        #expect(model.phase == .revealed)
        #expect(model.hits == 3)
    }

    @Test func wordsTheCardAndTheStake() {
        #expect(WhoKnowsModel.status(.answerAboutYou, remaining: 5, partner: "Leo") == "Answer 5 about yourself")
        #expect(WhoKnowsModel.status(.guessAboutPartner, remaining: 5, partner: "Leo") == "Guess 5 about Leo")
        #expect(WhoKnowsModel.status(.waitingForPartner, remaining: 0, partner: "Mia") == "Waiting for Mia")
        #expect(WhoKnowsModel.status(.unpaired, remaining: 5, partner: "Mia") == "Pair up to play")
        #expect(WhoKnowsModel.scoreLine(GuessTally(mine: 31, partner: 12), me: "Mia", partner: "Leo") == "Mia 31 · 12 Leo")
        #expect(WhoKnowsModel.stake(GuessTally(mine: 31, partner: 12), partner: "Leo")
            == "Loser plans Friday's date: that's Leo, so far")
        #expect(WhoKnowsModel.stake(GuessTally(mine: 4, partner: 4), partner: "Leo") == "Loser plans Friday's date")
    }
}
