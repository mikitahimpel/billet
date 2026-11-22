/// An episode, a beat or a suspect: lowercase words joined by hyphens, a letter first, at most 40
/// characters. The app's own content names them; the server only checks the shape.
public struct StoryId: Codable, Hashable, Sendable {
  public let rawValue: String

  public init?(rawValue: String) {
    guard Self.isValid(rawValue) else { return nil }
    self.rawValue = rawValue
  }

  static func isValid(_ text: String) -> Bool {
    guard text.utf8.count <= 40, text.utf8.first.map({ $0 >= 97 && $0 <= 122 }) == true else {
      return false
    }
    return text.split(separator: "-", omittingEmptySubsequences: false).allSatisfy { word in
      !word.isEmpty && word.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) }
    }
  }

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let id = StoryId(rawValue: value) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "StoryId: lowercase words joined by hyphens, at most 40 characters"
        ))
    }
    self = id
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// `found`: a beat's clue was found. `named`: a suspect was named.
public enum StoryMarkKind: String, Codable, Hashable, Sendable {
  case found, named
}

/// `ref` is the beat id for `found` and the suspect id for `named`. `at` is epoch milliseconds.
public struct StoryMark: Codable, Hashable, Sendable {
  public let episode: StoryId
  public let kind: StoryMarkKind
  public let ref: StoryId
  public let at: Int

  public init(episode: StoryId, kind: StoryMarkKind, ref: StoryId, at: Int) {
    self.episode = episode
    self.kind = kind
    self.ref = ref
    self.at = at
  }
}

/// Every mark of this user and of the partner. The partner's `named` marks of an episode are left
/// out until this user has named a suspect in it.
public struct StoryResponse: Codable, Hashable, Sendable {
  public let mine: [StoryMark]
  public let partner: [StoryMark]

  public init(mine: [StoryMark], partner: [StoryMark]) {
    self.mine = mine
    self.partner = partner
  }
}

/// The same mark again changes nothing; a second `named` in an episode never replaces the first.
public struct StoryMarkRequest: Codable, Hashable, Sendable {
  public let episode: StoryId
  public let kind: StoryMarkKind
  public let ref: StoryId

  public init(episode: StoryId, kind: StoryMarkKind, ref: StoryId) {
    self.episode = episode
    self.kind = kind
    self.ref = ref
  }
}
