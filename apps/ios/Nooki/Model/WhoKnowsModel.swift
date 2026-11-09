import FeatureGames
import Foundation
import Observation
import Transport
import Wire

/// Today's Who knows who round as this user plays it. One partner, the subject, answers five questions about
/// themselves while the other guesses; the room keeps each side's answers hidden until both are done, then opens them
/// together. The partner's progress and the reveal also arrive over the room socket.
///
/// The rules live in `WhoKnowsMachine` (FeatureGames); this is its store with the question catalog and the screen's
/// words around it.
@Observable
final class WhoKnowsModel {
    enum Phase: Equatable {
        case loading, answerAboutYou, guessAboutPartner, waitingForPartner, revealed, unpaired, offline
    }

    /// What the room pays once both partners finish a round, and for each right guess (`rewardForEarn` on the server).
    nonisolated static let roundCoins = 10
    nonisolated static let hitCoins = 2

    private(set) var catalog: [Int: GuessQuestion]

    @ObservationIgnored private let store: WhoKnowsStore

    /// Without `sync` or `viewer` the account has no partner and the round is `unpaired`.
    init(sync: WhoKnowsSync?, viewer: UserId?, catalog: [GuessQuestion]) {
        store = .whoKnows(sync, viewer: viewer)
        self.catalog = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
    }

    private var round: WhoKnowsMachine.Round? {
        if case .playing(let round) = store.state { round } else { nil }
    }

    var phase: Phase {
        switch store.state {
        case .unpaired: return .unpaired
        case .unread: return .loading
        case .unreachable: return .offline
        case .playing(let round):
            if round.response.reveal != nil { return .revealed }
            if round.next != nil { return round.isSubject ? .answerAboutYou : .guessAboutPartner }
            return .waitingForPartner
        }
    }

    /// Today's round as the room last answered it.
    var response: GuessResponse? { round?.response }
    /// The last answer didn't reach the room; its question is open again.
    var unsent: Bool { round?.unsent ?? false }
    var isSubject: Bool { round?.isSubject ?? false }

    /// This user's answers, the room's and the ones still on their way.
    var answers: [GuessAnswer] { round?.answers ?? [] }

    var total: Int { response?.round.questions.count ?? 5 }
    var remaining: Int { max(0, total - answers.count) }
    var partnerAnswered: Int { response?.partnerAnswered ?? 0 }
    var reveal: [GuessReveal] { response?.reveal ?? [] }
    var score: GuessScore? { response?.score }
    var hits: Int { reveal.filter(\.hit).count }
    /// What the revealed round paid the pair.
    var coinsEarned: Int { response?.reveal == nil ? 0 : Self.roundCoins + Self.hitCoins * hits }

    /// The next question to answer, in round order; nil once every one is answered, or while the catalog lacks it.
    var current: GuessQuestion? { round?.next.flatMap { catalog[$0] } }

    /// Whether the round asks a question this phone's catalog doesn't have yet.
    var lacksQuestions: Bool {
        response?.round.questions.contains { catalog[$0] == nil } ?? false
    }

    func question(_ id: Int) -> GuessQuestion? { catalog[id] }

    func use(_ questions: [GuessQuestion]) {
        for question in questions { catalog[question.id] = question }
    }

    func load() async {
        store.send(.loadAsked)
        await store.until { [self] in !isReading }
    }

    private var isReading: Bool {
        switch store.state {
        case .unpaired: false
        case .unread(_, let read), .unreachable(_, let read): read.isReading
        case .playing(let round): round.read.isReading
        }
    }

    /// Locks `option` for the current question and sends it. The screen moves on at once; an answer that doesn't
    /// reach the room opens its question again and sets `unsent`. True once the room has taken it.
    @discardableResult
    func answer(_ option: Int) async -> Bool {
        guard let question = current, question.options.indices.contains(option) else { return false }
        store.send(.answerTapped(question: question.id, option: option))
        await store.until { [self] in
            !(round?.pending.contains { $0.question == question.id } ?? false) && !isReading
        }
        let taken = GuessAnswer(question: question.id, option: option)
        return !unsent && (response?.answers.contains(taken) ?? false)
    }

    /// The partner's count of locked answers, from the room's socket.
    func progressed(round: String, answered: Int) {
        store.send(.progressed(round: round, answered: answered))
    }

    /// Both partners finished the round: every answer, and the score after it, from the room's socket.
    func revealed(round: String, reveal: [GuessReveal], score: GuessScore) {
        store.send(.revealed(round: round, reveal: reveal, score: score))
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
