/// A film or a show as search shows it. `runtime` is minutes, for a film; `seasons` for a show;
/// `rating` is TMDB's audience score, 0 to 10.
public struct TitleSummary: Codable, Hashable, Sendable {
  public let kind: ListMediaKind
  public let tmdb: Int
  public let title: String
  public let year: Int?
  public let posterPath: String?
  public let rating: Double?
  public let runtime: Int?
  public let seasons: Int?

  public init(
    kind: ListMediaKind, tmdb: Int, title: String, year: Int? = nil, posterPath: String? = nil,
    rating: Double? = nil, runtime: Int? = nil, seasons: Int? = nil
  ) {
    self.kind = kind
    self.tmdb = tmdb
    self.title = title
    self.year = year
    self.posterPath = posterPath
    self.rating = rating
    self.runtime = runtime
    self.seasons = seasons
  }

  private enum CodingKeys: String, CodingKey {
    case kind, tmdb, title, year, posterPath, rating, runtime, seasons
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decode(ListMediaKind.self, forKey: .kind)
    tmdb = try container.decode(Int.self, forKey: .tmdb)
    title = try container.decode(String.self, forKey: .title)
    year = try container.decodeOptionalKey(Int.self, forKey: .year)
    posterPath = try container.decodeOptionalKey(String.self, forKey: .posterPath)
    rating = try container.decodeOptionalKey(Double.self, forKey: .rating)
    runtime = try container.decodeOptionalKey(Int.self, forKey: .runtime)
    seasons = try container.decodeOptionalKey(Int.self, forKey: .seasons)
  }
}

/// `GET /v1/titles/search?q=&lang=`: the best matches first, films and shows only.
public struct TitleSearchResponse: Codable, Hashable, Sendable {
  public let results: [TitleSummary]

  public init(results: [TitleSummary]) {
    self.results = results
  }
}

/// A streaming service, a shop or a rental, as JustWatch names it.
public struct WatchProvider: Codable, Hashable, Sendable {
  public let id: Int
  public let name: String
  public let logoPath: String?

  public init(id: Int, name: String, logoPath: String? = nil) {
    self.id = id
    self.name = name
    self.logoPath = logoPath
  }

  private enum CodingKeys: String, CodingKey {
    case id, name, logoPath
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    logoPath = try container.decodeOptionalKey(String.self, forKey: .logoPath)
  }
}

/// Where the title can be watched in `country`, from JustWatch through TMDB. `stream` is part of a
/// subscription; `rentOrBuy` costs extra. `link` is TMDB's page that lists them.
public struct WatchOptions: Codable, Hashable, Sendable {
  public let country: String
  public let link: String?
  public let stream: [WatchProvider]
  public let rentOrBuy: [WatchProvider]

  public init(
    country: String, link: String? = nil, stream: [WatchProvider] = [],
    rentOrBuy: [WatchProvider] = []
  ) {
    self.country = country
    self.link = link
    self.stream = stream
    self.rentOrBuy = rentOrBuy
  }

  private enum CodingKeys: String, CodingKey {
    case country, link, stream, rentOrBuy
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    country = try container.decode(String.self, forKey: .country)
    link = try container.decodeOptionalKey(String.self, forKey: .link)
    stream = try container.decode([WatchProvider].self, forKey: .stream)
    rentOrBuy = try container.decode([WatchProvider].self, forKey: .rentOrBuy)
  }
}

/// `GET /v1/titles/:kind/:tmdb?country=&lang=`: the card's details.
public struct TitleDetails: Codable, Hashable, Sendable {
  public let summary: TitleSummary
  public let backdropPath: String?
  public let overview: String
  public let genres: [String]
  public let watch: WatchOptions

  public init(
    summary: TitleSummary, backdropPath: String? = nil, overview: String, genres: [String],
    watch: WatchOptions
  ) {
    self.summary = summary
    self.backdropPath = backdropPath
    self.overview = overview
    self.genres = genres
    self.watch = watch
  }

  private enum CodingKeys: String, CodingKey {
    case backdropPath, overview, genres, watch
  }

  public init(from decoder: any Decoder) throws {
    summary = try TitleSummary(from: decoder)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    backdropPath = try container.decodeOptionalKey(String.self, forKey: .backdropPath)
    overview = try container.decode(String.self, forKey: .overview)
    genres = try container.decode([String].self, forKey: .genres)
    watch = try container.decode(WatchOptions.self, forKey: .watch)
  }

  public func encode(to encoder: any Encoder) throws {
    try summary.encode(to: encoder)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(backdropPath, forKey: .backdropPath)
    try container.encode(overview, forKey: .overview)
    try container.encode(genres, forKey: .genres)
    try container.encode(watch, forKey: .watch)
  }
}
