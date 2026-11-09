import BilletKit
import Foundation
import Transport
import Wire

/// Today's Who knows who round: the subject answers five questions about themselves while the
/// other guesses; the room hides each side's answers until both are done. Progress and the reveal
/// also arrive over the room socket.
public enum WhoKnowsMachine: Machine {

  /// Why the room didn't take an answer.
  public enum Failure: Error, Equatable, Sendable {
    /// The network or the server: the answer may go again.
    case unreachable
    /// The room took another option for the question already, or the day ended: its own view is
    /// the truth, so it is read again.
    case refused

    public init(_ error: TransportError) {
      switch error {
      case .api(.invalidRequest): self = .refused
      case .api, .network, .status, .maintenance, .encoding, .decoding: self = .unreachable
      }
    }
  }

  public struct Round: Equatable, Sendable {
    public let viewer: UserId
    /// Today's round as the room last answered it, with the socket's frames merged in.
    public var response: GuessResponse
    /// Answers tapped here that the room hasn't confirmed yet, so the screen moves on at once.
    public var pending: [GuessAnswer] = []
    /// The last answer didn't reach the room; its question is open again.
    public var unsent = false
    public var read: GameRead

    public var isSubject: Bool { response.round.subject == viewer }

    /// This user's answers, the room's and the ones still on their way.
    public var answers: [GuessAnswer] {
      let confirmed = response.answers
      return confirmed
        + pending.filter { answer in !confirmed.contains { $0.question == answer.question } }
    }

    /// The next question to answer, in round order; nil once every one is answered.
    public var next: Int? {
      let done = Set(answers.map(\.question))
      return response.round.questions.first { !done.contains($0) }
    }
  }

  public enum State: Equatable, Sendable {
    /// No partner or no account: nothing to read or play.
    case unpaired
    /// Nothing known from the room yet.
    case unread(UserId, GameRead)
    /// The last read didn't reach the room, and nothing is known from it.
    case unreachable(UserId, GameRead)
    case playing(Round)

    public static func initial(viewer: UserId?) -> State {
      viewer.map { .unread($0, .idle(last: 0)) } ?? .unpaired
    }
  }

  public enum Event: Equatable, Sendable {
    // From the shell
    case loadAsked
    /// The partner's count of locked answers, from the room's socket.
    case progressed(round: String, answered: Int)
    /// Both partners finished the round, from the room's socket.
    case revealed(round: String, reveal: [GuessReveal], score: GuessScore)
    // From the screen
    case answerTapped(question: Int, option: Int)
    // Results
    case read(GuessResponse, request: Int)
    case readFailed(request: Int)
    case answered(question: Int, GuessResponse)
    case answerFailed(question: Int, Failure)
  }

  public enum Output: Equatable, Sendable {
    case read(request: Int)
    case answer(GuessAnswerRequest)
  }

  public static func transition(_ state: State, _ event: Event) -> (State, [Output]) {
    switch state {
    case .unpaired:
      switch event {
      case .loadAsked, .progressed, .revealed, .answerTapped, .read, .readFailed, .answered,
        .answerFailed:
        return (state, [])
      }

    case .unread(let viewer, let read), .unreachable(let viewer, let read):
      switch event {
      case .loadAsked:
        guard let (next, request) = read.next() else { return (state, []) }
        return (state.with(read: next), [.read(request: request)])
      case .read(let response, let request):
        guard read.isReading else { return (state, []) }
        return (
          .playing(Round(viewer: viewer, response: response, read: read.answered(request))), []
        )
      case .readFailed(let request):
        guard read.answered(request) != read else { return (state, []) }
        return (.unreachable(viewer, read.answered(request)), [])
      case .progressed, .revealed, .answerTapped, .answered, .answerFailed:
        return (state, [])
      }

    case .playing(var round):
      switch event {
      case .loadAsked:
        guard let (next, request) = round.read.next() else { return (state, []) }
        round.read = next
        return (.playing(round), [.read(request: request)])
      case .read(let response, let request):
        round.read = round.read.answered(request)
        round.apply(response)
        return (.playing(round), [])
      case .readFailed(let request):
        round.read = round.read.answered(request)
        return (.playing(round), [])

      case .progressed(let id, let answered):
        let response = round.response
        guard response.round.id == id else { return (state, []) }
        round.apply(
          GuessResponse(
            round: response.round, answers: response.answers, partnerAnswered: answered,
            reveal: response.reveal, score: response.score))
        return (.playing(round), [])
      case .revealed(let id, let reveal, let score):
        let response = round.response
        guard response.round.id == id else { return (state, []) }
        round.apply(
          GuessResponse(
            round: response.round, answers: response.answers,
            partnerAnswered: response.round.questions.count, reveal: reveal, score: score))
        return (.playing(round), [])

      case .answerTapped(let question, let option):
        guard round.response.reveal == nil, round.next == question else { return (state, []) }
        round.pending.append(GuessAnswer(question: question, option: option))
        round.unsent = false
        let request = GuessAnswerRequest(
          round: round.response.round.id, question: question, option: option)
        return (.playing(round), [.answer(request)])
      case .answered(let question, let response):
        round.pending.removeAll { $0.question == question }
        round.apply(response)
        return (.playing(round), [])
      case .answerFailed(let question, let failure):
        guard round.pending.contains(where: { $0.question == question }) else {
          return (state, [])
        }
        round.pending.removeAll { $0.question == question }
        switch failure {
        case .unreachable:
          round.unsent = true
          return (.playing(round), [])
        case .refused:
          guard let (next, request) = round.read.next() else { return (.playing(round), []) }
          round.read = next
          return (.playing(round), [.read(request: request)])
        }
      }
    }
  }
}

extension WhoKnowsMachine.State {
  fileprivate func with(read: GameRead) -> Self {
    switch self {
    case .unread(let viewer, _): .unread(viewer, read)
    case .unreachable(let viewer, _): .unreachable(viewer, read)
    case .unpaired, .playing: self
    }
  }
}

extension WhoKnowsMachine.Round {
  /// Takes the room's view. Within one round nothing goes back: answers and the partner's count
  /// only grow and the reveal stays, so a late answer to an earlier request or socket frame can't
  /// undo a newer one.
  mutating func apply(_ next: GuessResponse) {
    let old = response
    // Round ids are `YYYY-MM-DD`, so they order as text: a late answer about an earlier day is
    // dropped.
    if next.round.id < old.round.id { return }
    guard old.round.id == next.round.id else {
      response = next
      return
    }
    let added = next.answers.filter { answer in
      !old.answers.contains { $0.question == answer.question }
    }
    let reveal = next.reveal ?? old.reveal
    response = GuessResponse(
      round: next.round, answers: old.answers + added,
      partnerAnswered: max(old.partnerAnswered, next.partnerAnswered), reveal: reveal,
      score: next.reveal != nil || old.reveal == nil ? next.score : old.score)
  }
}
