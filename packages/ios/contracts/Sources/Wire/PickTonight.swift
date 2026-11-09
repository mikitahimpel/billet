/// ✕ not tonight, 👁 seen it, ♥ want to.
public enum PickChoice: String, Codable, Hashable, Sendable {
  case pass, seen, want
}

/// An item on the pair's To watch list, or a TMDB title that is not on it.
public enum PickTitle: Codable, Hashable, Sendable {
  case item(IdempotencyKey)
  case title(kind: ListMediaKind, tmdb: Int)

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case item, kind, tmdb
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    switch tag {
    case "Item":
      self = .item(try container.decode(IdempotencyKey.self, forKey: .item))
    case "Title":
      self = .title(
        kind: try container.decode(ListMediaKind.self, forKey: .kind),
        tmdb: try container.decode(Int.self, forKey: .tmdb))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .item(let item):
      try container.encode("Item", forKey: .tag)
      try container.encode(item, forKey: .item)
    case .title(let kind, let tmdb):
      try container.encode("Title", forKey: .tag)
      try container.encode(kind, forKey: .kind)
      try container.encode(tmdb, forKey: .tmdb)
    }
  }
}

public struct PickSwipe: Codable, Hashable, Sendable {
  public let title: PickTitle
  public let choice: PickChoice
  /// Epoch milliseconds.
  public let at: Int

  public init(title: PickTitle, choice: PickChoice, at: Int) {
    self.title = title
    self.choice = choice
    self.at = at
  }
}

/// `name` and `posterPath` are what the second swipe sent; `at` (epoch milliseconds) is when it
/// made the match.
public struct PickMatch: Codable, Hashable, Sendable {
  public let title: PickTitle
  public let name: String
  public let posterPath: String?
  public let at: Int

  public init(title: PickTitle, name: String, posterPath: String? = nil, at: Int) {
    self.title = title
    self.name = name
    self.posterPath = posterPath
    self.at = at
  }

  private enum CodingKeys: String, CodingKey {
    case title, name, posterPath, at
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(PickTitle.self, forKey: .title)
    name = try container.decode(String.self, forKey: .name)
    posterPath = try container.decodeOptionalKey(String.self, forKey: .posterPath)
    at = try container.decode(Int.self, forKey: .at)
  }
}

/// The last 24 hours as this user sees them. `partnerPicked` counts the partner's swipes;
/// `matches` are newest first; `match` is set on the answer to the swipe that made one.
public struct PickTonightResponse: Codable, Hashable, Sendable {
  public let swipes: [PickSwipe]
  public let partnerPicked: Int
  public let matches: [PickMatch]
  public let match: PickMatch?

  public init(
    swipes: [PickSwipe] = [], partnerPicked: Int = 0, matches: [PickMatch] = [],
    match: PickMatch? = nil
  ) {
    self.swipes = swipes
    self.partnerPicked = partnerPicked
    self.matches = matches
    self.match = match
  }

  private enum CodingKeys: String, CodingKey {
    case swipes, partnerPicked, matches, match
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    swipes = try container.decode([PickSwipe].self, forKey: .swipes)
    partnerPicked = try container.decode(Int.self, forKey: .partnerPicked)
    matches = try container.decode([PickMatch].self, forKey: .matches)
    match = try container.decodeOptionalKey(PickMatch.self, forKey: .match)
  }
}

/// The same choice on a card again within the session changes nothing; another replaces it.
public struct PickSwipeRequest: Codable, Hashable, Sendable {
  public let title: PickTitle
  public let choice: PickChoice
  public let name: String
  public let posterPath: String?

  public init(title: PickTitle, choice: PickChoice, name: String, posterPath: String? = nil) {
    self.title = title
    self.choice = choice
    self.name = name
    self.posterPath = posterPath
  }

  private enum CodingKeys: String, CodingKey {
    case title, choice, name, posterPath
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decode(PickTitle.self, forKey: .title)
    choice = try container.decode(PickChoice.self, forKey: .choice)
    name = try container.decode(String.self, forKey: .name)
    posterPath = try container.decodeOptionalKey(String.self, forKey: .posterPath)
  }
}
