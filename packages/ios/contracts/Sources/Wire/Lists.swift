/// `groceries` is a plain checklist; every other kind is a "we want to" list whose ticks earn.
public enum ListKind: String, Codable, Hashable, Sendable, CaseIterable {
  case watch
  case groceries
  case travel
  case food
  case books
  case bucket
  case custom
}

public enum ListTint: String, Codable, Hashable, Sendable, CaseIterable {
  case honey
  case blush
  case sky
  case sage
  case lilac
  case sun
  case coral
}

/// An SF Symbol on a tinted tile. The symbol is lowercase letters, digits and dots.
public struct ListIcon: Codable, Hashable, Sendable {
  public let symbol: String
  public let tint: ListTint

  public init(symbol: String, tint: ListTint) {
    self.symbol = symbol
    self.tint = tint
  }
}

public enum ListMediaKind: String, Codable, Hashable, Sendable {
  case movie
  case tv
}

/// A film or a show on TMDB. Its ids are counted per kind, so the kind is part of the id. The
/// item's text is its title; `year` and `posterPath` are what the grid draws without asking TMDB.
public struct ListMedia: Codable, Hashable, Sendable {
  public let kind: ListMediaKind
  public let tmdb: Int
  public let year: Int?
  /// A TMDB image file such as `/qJeU7KM4nT2C1WpOrwPcSDGFUWE.jpg`.
  public let posterPath: String?

  public init(kind: ListMediaKind, tmdb: Int, year: Int? = nil, posterPath: String? = nil) {
    self.kind = kind
    self.tmdb = tmdb
    self.year = year
    self.posterPath = posterPath
  }

  private enum CodingKeys: String, CodingKey {
    case kind, tmdb, year, posterPath
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    kind = try container.decode(ListMediaKind.self, forKey: .kind)
    tmdb = try container.decode(Int.self, forKey: .tmdb)
    year = try container.decodeOptionalKey(Int.self, forKey: .year)
    posterPath = try container.decodeOptionalKey(String.self, forKey: .posterPath)
  }
}

/// What a partner says about an item apart from its tick. `quantity` is up to 40 characters,
/// `note` up to 500; `icon` and `aisle` are lowercase slugs; `country` is ISO 3166-1 alpha-2.
/// On a travel list an item with a `country` is that country, or with `place` a city or place in
/// it; `visitedIn` is a month such as `2026-10` and `moments` up to 10 moment ids.
public struct ListItemDetails: Hashable, Sendable {
  public var quantity: String?
  public var note: String?
  public var icon: String?
  public var aisle: String?
  public var media: ListMedia?
  public var country: String?
  public var place: Bool?
  public var visitedIn: String?
  public var moments: [String]?

  public init(
    quantity: String? = nil, note: String? = nil, icon: String? = nil, aisle: String? = nil,
    media: ListMedia? = nil, country: String? = nil, place: Bool? = nil, visitedIn: String? = nil,
    moments: [String]? = nil
  ) {
    self.quantity = quantity
    self.note = note
    self.icon = icon
    self.aisle = aisle
    self.media = media
    self.country = country
    self.place = place
    self.visitedIn = visitedIn
    self.moments = moments
  }

  enum Keys: String, CodingKey {
    case quantity, note, icon, aisle, media, country, place, visitedIn, moments
  }

  init<K: CodingKey>(from container: KeyedDecodingContainer<K>, keys: (Keys) -> K) throws {
    quantity = try container.decodeOptionalKey(String.self, forKey: keys(.quantity))
    note = try container.decodeOptionalKey(String.self, forKey: keys(.note))
    icon = try container.decodeOptionalKey(String.self, forKey: keys(.icon))
    aisle = try container.decodeOptionalKey(String.self, forKey: keys(.aisle))
    media = try container.decodeOptionalKey(ListMedia.self, forKey: keys(.media))
    country = try container.decodeOptionalKey(String.self, forKey: keys(.country))
    place = try container.decodeOptionalKey(Bool.self, forKey: keys(.place))
    visitedIn = try container.decodeOptionalKey(String.self, forKey: keys(.visitedIn))
    moments = try container.decodeOptionalKey([String].self, forKey: keys(.moments))
  }

  func encode<K: CodingKey>(to container: inout KeyedEncodingContainer<K>, keys: (Keys) -> K)
    throws
  {
    try container.encodeIfPresent(quantity, forKey: keys(.quantity))
    try container.encodeIfPresent(note, forKey: keys(.note))
    try container.encodeIfPresent(icon, forKey: keys(.icon))
    try container.encodeIfPresent(aisle, forKey: keys(.aisle))
    try container.encodeIfPresent(media, forKey: keys(.media))
    try container.encodeIfPresent(country, forKey: keys(.country))
    try container.encodeIfPresent(place, forKey: keys(.place))
    try container.encodeIfPresent(visitedIn, forKey: keys(.visitedIn))
    try container.encodeIfPresent(moments, forKey: keys(.moments))
  }
}

/// Wire form of the contracts `ListItem`. `author` and `addedAt` are the room's; `doneBy` and
/// `doneAt` are both present once it is ticked. Times are epoch milliseconds.
public struct ListItem: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let text: String
  public let author: UserId
  public let addedAt: Int
  public let doneBy: UserId?
  public let doneAt: Int?
  public let details: ListItemDetails
  /// The members who want it, in the order they said so.
  public let wants: [UserId]

  public init(
    id: IdempotencyKey, text: String, author: UserId, addedAt: Int, doneBy: UserId? = nil,
    doneAt: Int? = nil, details: ListItemDetails = ListItemDetails(), wants: [UserId] = []
  ) {
    self.id = id
    self.text = text
    self.author = author
    self.addedAt = addedAt
    self.doneBy = doneBy
    self.doneAt = doneAt
    self.details = details
    self.wants = wants
  }

  private enum CodingKeys: String, CodingKey {
    case id, text, author, addedAt, doneBy, doneAt, wants
    case quantity, note, icon, aisle, media, country, place, visitedIn, moments
  }

  private static func key(_ detail: ListItemDetails.Keys) -> CodingKeys {
    switch detail {
    case .quantity: .quantity
    case .note: .note
    case .icon: .icon
    case .aisle: .aisle
    case .media: .media
    case .country: .country
    case .place: .place
    case .visitedIn: .visitedIn
    case .moments: .moments
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(IdempotencyKey.self, forKey: .id)
    text = try container.decode(String.self, forKey: .text)
    author = try container.decode(UserId.self, forKey: .author)
    addedAt = try container.decode(Int.self, forKey: .addedAt)
    doneBy = try container.decodeOptionalKey(UserId.self, forKey: .doneBy)
    doneAt = try container.decodeOptionalKey(Int.self, forKey: .doneAt)
    details = try ListItemDetails(from: container, keys: Self.key)
    wants = try container.decode([UserId].self, forKey: .wants)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(text, forKey: .text)
    try container.encode(author, forKey: .author)
    try container.encode(addedAt, forKey: .addedAt)
    try container.encodeIfPresent(doneBy, forKey: .doneBy)
    try container.encodeIfPresent(doneAt, forKey: .doneAt)
    try details.encode(to: &container, keys: Self.key)
    try container.encode(wants, forKey: .wants)
  }
}

/// A list both partners see and edit. `items` are in the order they were added, oldest first.
public struct SharedList: Codable, Hashable, Sendable {
  public let id: IdempotencyKey
  public let kind: ListKind
  /// 1 to 60 characters, not only whitespace.
  public let title: String
  public let icon: ListIcon
  public let items: [ListItem]

  public init(id: IdempotencyKey, kind: ListKind, title: String, icon: ListIcon, items: [ListItem])
  {
    self.id = id
    self.kind = kind
    self.title = title
    self.icon = icon
    self.items = items
  }
}

/// A change either partner makes. `key` is made once per change and repeated on each retry: the
/// room applies a key once. An edit sets every detail, so one left out is cleared. Item text is 1
/// to 300 characters, not only whitespace.
public enum ListCommand: Codable, Hashable, Sendable {
  case createList(
    key: IdempotencyKey, list: IdempotencyKey, kind: ListKind, title: String, icon: ListIcon)
  case renameList(key: IdempotencyKey, list: IdempotencyKey, title: String, icon: ListIcon)
  case deleteList(key: IdempotencyKey, list: IdempotencyKey)
  case addItem(
    key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey, text: String,
    details: ListItemDetails)
  case editItem(
    key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey, text: String,
    details: ListItemDetails)
  /// The first tick wins: ticking an item already ticked changes nothing.
  case tickItem(key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey)
  case untickItem(key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey)
  case deleteItem(key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey)
  /// The caller wants the item, or no longer does.
  case wantItem(key: IdempotencyKey, list: IdempotencyKey, item: IdempotencyKey, wants: Bool)

  public var key: IdempotencyKey {
    switch self {
    case .createList(let key, _, _, _, _), .renameList(let key, _, _, _),
      .deleteList(let key, _), .addItem(let key, _, _, _, _), .editItem(let key, _, _, _, _),
      .tickItem(let key, _, _), .untickItem(let key, _, _), .deleteItem(let key, _, _),
      .wantItem(let key, _, _, _):
      key
    }
  }

  private enum CodingKeys: String, CodingKey {
    case tag = "_tag"
    case key, list, kind, title, icon, item, text, wants
    case quantity, note, aisle, media, country, place, visitedIn, moments
  }

  /// `icon` names the list's tile on a list and the item's icon on an item: one wire key.
  private static func key(_ detail: ListItemDetails.Keys) -> CodingKeys {
    switch detail {
    case .quantity: .quantity
    case .note: .note
    case .icon: .icon
    case .aisle: .aisle
    case .media: .media
    case .country: .country
    case .place: .place
    case .visitedIn: .visitedIn
    case .moments: .moments
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let tag = try container.decode(String.self, forKey: .tag)
    let key = try container.decode(IdempotencyKey.self, forKey: .key)
    let list = try container.decode(IdempotencyKey.self, forKey: .list)
    switch tag {
    case "CreateList":
      self = .createList(
        key: key, list: list, kind: try container.decode(ListKind.self, forKey: .kind),
        title: try container.decode(String.self, forKey: .title),
        icon: try container.decode(ListIcon.self, forKey: .icon))
    case "RenameList":
      self = .renameList(
        key: key, list: list, title: try container.decode(String.self, forKey: .title),
        icon: try container.decode(ListIcon.self, forKey: .icon))
    case "DeleteList":
      self = .deleteList(key: key, list: list)
    case "AddItem":
      self = .addItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item),
        text: try container.decode(String.self, forKey: .text),
        details: try ListItemDetails(from: container, keys: Self.key))
    case "EditItem":
      self = .editItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item),
        text: try container.decode(String.self, forKey: .text),
        details: try ListItemDetails(from: container, keys: Self.key))
    case "TickItem":
      self = .tickItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item))
    case "UntickItem":
      self = .untickItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item))
    case "DeleteItem":
      self = .deleteItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item))
    case "WantItem":
      self = .wantItem(
        key: key, list: list, item: try container.decode(IdempotencyKey.self, forKey: .item),
        wants: try container.decode(Bool.self, forKey: .wants))
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .tag, in: container, debugDescription: "unknown _tag \(tag)")
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key, forKey: .key)
    switch self {
    case .createList(_, let list, let kind, let title, let icon):
      try container.encode("CreateList", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(kind, forKey: .kind)
      try container.encode(title, forKey: .title)
      try container.encode(icon, forKey: .icon)
    case .renameList(_, let list, let title, let icon):
      try container.encode("RenameList", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(title, forKey: .title)
      try container.encode(icon, forKey: .icon)
    case .deleteList(_, let list):
      try container.encode("DeleteList", forKey: .tag)
      try container.encode(list, forKey: .list)
    case .addItem(_, let list, let item, let text, let details):
      try container.encode("AddItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
      try container.encode(text, forKey: .text)
      try details.encode(to: &container, keys: Self.key)
    case .editItem(_, let list, let item, let text, let details):
      try container.encode("EditItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
      try container.encode(text, forKey: .text)
      try details.encode(to: &container, keys: Self.key)
    case .tickItem(_, let list, let item):
      try container.encode("TickItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
    case .untickItem(_, let list, let item):
      try container.encode("UntickItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
    case .deleteItem(_, let list, let item):
      try container.encode("DeleteItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
    case .wantItem(_, let list, let item, let wants):
      try container.encode("WantItem", forKey: .tag)
      try container.encode(list, forKey: .list)
      try container.encode(item, forKey: .item)
      try container.encode(wants, forKey: .wants)
    }
  }
}

public struct ListsResponse: Codable, Hashable, Sendable {
  public let lists: [SharedList]

  public init(lists: [SharedList]) {
    self.lists = lists
  }
}

/// One change, with the caller's UTC offset for the daily coin cap when the change may earn.
public struct ChangeListRequest: Codable, Hashable, Sendable {
  public let change: ListCommand
  public let utcOffsetSeconds: Int?

  public init(change: ListCommand, utcOffsetSeconds: Int? = nil) {
    self.change = change
    self.utcOffsetSeconds = utcOffsetSeconds
  }

  private enum CodingKeys: String, CodingKey {
    case change, utcOffsetSeconds
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    change = try container.decode(ListCommand.self, forKey: .change)
    utcOffsetSeconds = try container.decodeOptionalKey(Int.self, forKey: .utcOffsetSeconds)
  }
}
