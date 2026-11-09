public enum GuessTag: String, Codable, Hashable, Sendable, CaseIterable {
  case food, habits, past, music, money, us, dreams, quirks
}

/// `guess` is what the guesser reads, with `{name}` for the subject; `selfText` (`self` on the
/// wire) is the question as the subject reads it. `options` are always four, picked by index.
public struct GuessQuestion: Codable, Hashable, Sendable {
  public let id: Int
  public let guess: String
  public let selfText: String
  public let options: [String]
  public let tag: GuessTag

  public init(id: Int, guess: String, selfText: String, options: [String], tag: GuessTag) {
    self.id = id
    self.guess = guess
    self.selfText = selfText
    self.options = options
    self.tag = tag
  }

  private enum CodingKeys: String, CodingKey {
    case id, guess, options, tag
    case selfText = "self"
  }
}

/// `version` changes with the questions and is the response's ETag.
public struct GuessCatalogResponse: Codable, Hashable, Sendable {
  public let version: String
  public let questions: [GuessQuestion]

  public init(version: String, questions: [GuessQuestion]) {
    self.version = version
    self.questions = questions
  }
}

/// `id` is the room day, `YYYY-MM-DD`. `subject` answers about themselves, the other guesses.
/// A round not finished by `closesAt` (epoch milliseconds) is never scored.
public struct GuessRound: Codable, Hashable, Sendable {
  public let id: String
  public let subject: UserId
  public let questions: [Int]
  public let closesAt: Int

  public init(id: String, subject: UserId, questions: [Int], closesAt: Int) {
    self.id = id
    self.subject = subject
    self.questions = questions
    self.closesAt = closesAt
  }
}

/// The subject's truth, or the guesser's guess. `option` is 0 to 3.
public struct GuessAnswer: Codable, Hashable, Sendable {
  public let question: Int
  public let option: Int

  public init(question: Int, option: Int) {
    self.question = question
    self.option = option
  }
}

public struct GuessReveal: Codable, Hashable, Sendable {
  public let question: Int
  public let truth: Int
  public let guess: Int
  public let hit: Bool

  public init(question: Int, truth: Int, guess: Int, hit: Bool) {
    self.question = question
    self.truth = truth
    self.guess = guess
    self.hit = hit
  }
}

/// A point is a hit while guessing.
public struct GuessTally: Codable, Hashable, Sendable {
  public let mine: Int
  public let partner: Int

  public init(mine: Int = 0, partner: Int = 0) {
    self.mine = mine
    self.partner = partner
  }
}

/// The pair's score. `weekOf` is the Monday the current week started on, in room time;
/// `bestWeek` is each member's own highest week.
public struct GuessScore: Codable, Hashable, Sendable {
  public let weekOf: String
  public let week: GuessTally
  public let allTime: GuessTally
  public let bestWeek: GuessTally

  public init(
    weekOf: String, week: GuessTally = GuessTally(), allTime: GuessTally = GuessTally(),
    bestWeek: GuessTally = GuessTally()
  ) {
    self.weekOf = weekOf
    self.week = week
    self.allTime = allTime
    self.bestWeek = bestWeek
  }
}

/// The partner's answers stay hidden, counted in `partnerAnswered`, until both have answered
/// every question; then `reveal` holds each question in round order.
public struct GuessResponse: Codable, Hashable, Sendable {
  public let round: GuessRound
  public let answers: [GuessAnswer]
  public let partnerAnswered: Int
  public let reveal: [GuessReveal]?
  public let score: GuessScore

  public init(
    round: GuessRound, answers: [GuessAnswer] = [], partnerAnswered: Int = 0,
    reveal: [GuessReveal]? = nil, score: GuessScore
  ) {
    self.round = round
    self.answers = answers
    self.partnerAnswered = partnerAnswered
    self.reveal = reveal
    self.score = score
  }

  private enum CodingKeys: String, CodingKey {
    case round, answers, partnerAnswered, reveal, score
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    round = try container.decode(GuessRound.self, forKey: .round)
    answers = try container.decode([GuessAnswer].self, forKey: .answers)
    partnerAnswered = try container.decode(Int.self, forKey: .partnerAnswered)
    reveal = try container.decodeOptionalKey([GuessReveal].self, forKey: .reveal)
    score = try container.decode(GuessScore.self, forKey: .score)
  }
}

/// Locks: the same option again changes nothing, another one is 409.
public struct GuessAnswerRequest: Codable, Hashable, Sendable {
  public let round: String
  public let question: Int
  public let option: Int

  public init(round: String, question: Int, option: Int) {
    self.round = round
    self.question = question
    self.option = option
  }
}
