/// What a Who knows who question is about.
public enum GuessTag: String, Codable, Hashable, Sendable, CaseIterable {
  case food, habits, past, music, money, us, dreams, quirks
}

/// One question of the Who knows who catalog. `guess` is what the guesser reads, with `{name}` for
/// the subject's name; `selfText` (`self` on the wire) is the same question as the subject reads
/// it. `options` are always four, picked by index.
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

/// `GET /v1/guess/catalog`: every question. `version` changes with the questions and is the
/// response's ETag.
public struct GuessCatalogResponse: Codable, Hashable, Sendable {
  public let version: String
  public let questions: [GuessQuestion]

  public init(version: String, questions: [GuessQuestion]) {
    self.version = version
    self.questions = questions
  }
}

/// The pair's round of one room day: `id` is that day, `YYYY-MM-DD`. `subject` answers about
/// themselves and the other member guesses. `closesAt` (epoch milliseconds) is when the day ends;
/// a round not finished by then is never scored.
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

/// One locked answer: the subject's truth, or the guesser's guess. `option` is 0 to 3.
public struct GuessAnswer: Codable, Hashable, Sendable {
  public let question: Int
  public let option: Int

  public init(question: Int, option: Int) {
    self.question = question
    self.option = option
  }
}

/// One question opened after both members answered the whole round.
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

/// Points of this user and of the partner. A point is a hit while guessing.
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

/// `GET /v1/guess`, and the answer to an answer: today's round as this user sees it. `answers`
/// are this user's own; the partner's stay hidden, counted in `partnerAnswered`, until both have
/// answered every question. Then `reveal` holds each question in round order.
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

/// `POST /v1/guess/answers`: one answer to a question of today's round. It locks: the same
/// option again changes nothing, another one is `.api(.invalidRequest)` with status 409.
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
