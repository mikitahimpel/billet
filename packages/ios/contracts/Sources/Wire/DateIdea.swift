/// One Date Night card. `title` and `pitch` may hold `{cat}`, replaced with the cat's name.
public struct DateIdea: Codable, Hashable, Sendable {
  public enum Place: String, Codable, Hashable, Sendable, CaseIterable {
    case home, city, nature, apart
  }

  public enum Cost: String, Codable, Hashable, Sendable, CaseIterable {
    case free
    case cheap = "$"
    case nice = "$$"
  }

  public enum Length: String, Codable, Hashable, Sendable, CaseIterable {
    case hour = "1h"
    case evening, day
  }

  public enum Season: String, Codable, Hashable, Sendable, CaseIterable {
    case any, spring, summer, autumn, winter
  }

  /// `path` names a content hash, so it is cached for good; `color` (`#RRGGBB`) is its average,
  /// shown while it loads.
  public struct Art: Codable, Hashable, Sendable {
    public let path: String
    public let color: String

    public init(path: String, color: String) {
      self.path = path
      self.color = color
    }
  }

  public let id: Int
  public let title: String
  public let pitch: String
  public let place: Place
  public let cost: Cost
  public let time: Length
  public let season: Season
  public let art: Art

  public init(
    id: Int, title: String, pitch: String, place: Place, cost: Cost, time: Length,
    season: Season, art: Art
  ) {
    self.id = id
    self.title = title
    self.pitch = pitch
    self.place = place
    self.cost = cost
    self.time = time
    self.season = season
    self.art = art
  }
}

/// `version` changes with the ideas and is the response's ETag.
public struct DateCatalogResponse: Codable, Hashable, Sendable {
  public let version: String
  public let ideas: [DateIdea]

  public init(version: String, ideas: [DateIdea]) {
    self.version = version
    self.ideas = ideas
  }
}
