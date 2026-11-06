import Foundation
import Observation
import Transport
import Wire

/// Today's Who knows who round as this user plays it. One partner, the subject, answers five questions about
/// themselves while the other guesses; the room keeps each side's answers hidden until both are done, then opens them
/// together. The partner's progress and the reveal also arrive over the room socket.
@Observable
final class WhoKnowsModel {
    enum Phase: Equatable {
        case loading, answerAboutYou, guessAboutPartner, waitingForPartner, revealed, unpaired, offline
    }

    /// What the room pays once both partners finish a round, and for each right guess (`rewardForEarn` on the server).
    nonisolated static let roundCoins = 10
    nonisolated static let hitCoins = 2

    /// Today's round as the room last answered it.
    private(set) var response: GuessResponse?
    /// The room wasn't reachable on the last read.
    private(set) var offline = false
    /// The last answer didn't reach the room; its question is open again.
    private(set) var unsent = false
    /// Answers tapped here that the room hasn't confirmed yet, so the screen moves on at once.
    private(set) var pending: [GuessAnswer] = []
    private(set) var catalog: [Int: GuessQuestion]

    @ObservationIgnored private let sync: WhoKnowsSync?
    @ObservationIgnored private let viewer: UserId?

    /// Without `sync` or `viewer` the account has no partner and the round is `unpaired`.
    init(sync: WhoKnowsSync?, viewer: UserId?, catalog: [GuessQuestion]) {
        self.sync = sync
        self.viewer = viewer
        self.catalog = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    var phase: Phase {
        guard sync != nil, viewer != nil else { return .unpaired }
        guard let response else { return offline ? .offline : .loading }
        if response.reveal != nil { return .revealed }
        if answers.count < response.round.questions.count { return isSubject ? .answerAboutYou : .guessAboutPartner }
        return .waitingForPartner
    }

    var isSubject: Bool { response.map { $0.round.subject == viewer } ?? false }

    /// This user's answers, the room's and the ones still on their way.
    var answers: [GuessAnswer] {
        let confirmed = response?.answers ?? []
        return confirmed + pending.filter { answer in !confirmed.contains { $0.question == answer.question } }
    }

    var total: Int { response?.round.questions.count ?? 5 }
    var remaining: Int { max(0, total - answers.count) }
    var partnerAnswered: Int { response?.partnerAnswered ?? 0 }
    var reveal: [GuessReveal] { response?.reveal ?? [] }
    var score: GuessScore? { response?.score }
    var hits: Int { reveal.filter(\.hit).count }
    /// What the revealed round paid the pair.
    var coinsEarned: Int { response?.reveal == nil ? 0 : Self.roundCoins + Self.hitCoins * hits }

    /// The next question to answer, in round order; nil once every one is answered, or while the catalog lacks it.
    var current: GuessQuestion? {
        guard let response else { return nil }
        let done = Set(answers.map(\.question))
        return response.round.questions.first { !done.contains($0) }.flatMap { catalog[$0] }
    }

    /// Whether the round asks a question this phone's catalog doesn't have yet.
    var lacksQuestions: Bool {
        response?.round.questions.contains { catalog[$0] == nil } ?? false
    }

    func question(_ id: Int) -> GuessQuestion? { catalog[id] }

    func use(_ questions: [GuessQuestion]) {
        for question in questions { catalog[question.id] = question }
    }

    func load() async {
        guard let sync else { return }
        do throws(TransportError) {
            apply(try await sync.fetch())
            offline = false
        } catch {
            offline = true
        }
    }

    /// Locks `option` for the current question and sends it. The screen moves on at once; an answer that doesn't
    /// reach the room opens its question again and sets `unsent`.
    @discardableResult
    func answer(_ option: Int) async -> Bool {
        guard let sync, let response, let question = current, question.options.indices.contains(option) else {
            return false
        }
        pending.append(GuessAnswer(question: question.id, option: option))
        unsent = false
        let request = GuessAnswerRequest(round: response.round.id, question: question.id, option: option)
        do throws(TransportError) {
            let answered = try await sync.answer(request)
            pending.removeAll { $0.question == question.id }
            apply(answered)
            return true
        } catch {
            pending.removeAll { $0.question == question.id }
            if case .api(.invalidRequest) = error {
                // The room took another option for it already, or the day ended: its own view is the truth.
                await load()
            } else {
                unsent = true
            }
            return false
        }
    }

    /// The partner's count of locked answers, from the room's socket.
    func progressed(round: String, answered: Int) {
        guard let response, response.round.id == round else { return }
        apply(GuessResponse(round: response.round, answers: response.answers, partnerAnswered: answered,
                            reveal: response.reveal, score: response.score))
    }

    /// Both partners finished the round: every answer, and the score after it, from the room's socket.
    func revealed(round: String, reveal: [GuessReveal], score: GuessScore) {
        guard let response, response.round.id == round else { return }
        apply(GuessResponse(round: response.round, answers: response.answers,
                            partnerAnswered: response.round.questions.count, reveal: reveal, score: score))
    }

    /// Takes the room's view. Within one round nothing goes back: answers and the partner's count only grow and the
    /// reveal stays, so a late answer to an earlier request or socket frame can't undo a newer one.
    private func apply(_ next: GuessResponse) {
        // Round ids are `YYYY-MM-DD`, so they order as text: a late answer about an earlier day is dropped.
        if let old = response, next.round.id < old.round.id { return }
        guard let old = response, old.round.id == next.round.id else {
            response = next
            return
        }
        let added = next.answers.filter { answer in !old.answers.contains { $0.question == answer.question } }
        let reveal = next.reveal ?? old.reveal
        response = GuessResponse(round: next.round, answers: old.answers + added,
                                 partnerAnswered: max(old.partnerAnswered, next.partnerAnswered), reveal: reveal,
                                 score: next.reveal != nil || old.reveal == nil ? next.score : old.score)
    }

    // MARK: Words

    /// The question as this user reads it: in the second person for the subject, with the subject's name for the
    /// guesser.
    nonisolated static func text(_ question: GuessQuestion, isSubject: Bool, subjectName: String) -> String {
        isSubject ? question.selfText : question.guess.replacingOccurrences(of: "{name}", with: subjectName)
    }

    /// The Us tab card's line for the round.
    nonisolated static func status(_ phase: Phase, remaining: Int, partner: String) -> String {
        switch phase {
        case .loading: "Today's round"
        case .answerAboutYou: "Answer \(remaining) about yourself"
        case .guessAboutPartner: "Guess \(remaining) about \(partner)"
        case .waitingForPartner: "Waiting for \(partner)"
        case .revealed: "Results are in!"
        case .unpaired: "Pair up to play"
        case .offline: "Offline · try again soon"
        }
    }

    /// "Mia 31 · 12 Leo": this user first.
    nonisolated static func scoreLine(_ week: GuessTally, me: String, partner: String) -> String {
        "\(me) \(week.mine) · \(week.partner) \(partner)"
    }

    /// The week's stake, and who it falls on so far.
    nonisolated static func stake(_ week: GuessTally, partner: String) -> String {
        if week.mine < week.partner { return "Loser plans Friday's date: that's you, so far" }
        if week.partner < week.mine { return "Loser plans Friday's date: that's \(partner), so far" }
        return "Loser plans Friday's date"
    }
}
