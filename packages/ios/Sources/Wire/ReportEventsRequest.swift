/// The events the app may report about itself: a name, and for some a short detail from a closed
/// set or a catalogue id. No note, no image, no text, no time: the server stamps the time and adds
/// the pair. It records `InviteCreated`, `PairClaimed`, `NoteSent` and `AccountDeleted` itself, so
/// those are not here and are refused if sent. ``rule`` says what each name may carry.
public enum ClientEventName: String, Codable, Hashable, Sendable, CaseIterable {
  /// The app came to the front. At most one per launch.
  case appOpened = "AppOpened"
  /// This phone now has a billet widget. Reported once per widget kind (detail: the kind).
  case widgetAdded = "WidgetAdded"
  /// The user watched the opening to the end.
  case openingWatched = "OpeningWatched"
  /// The user skipped the opening.
  case openingSkipped = "OpeningSkipped"

  /// The cat was stroked.
  case catPetted = "CatPetted"
  /// The cat was fed: the day's shared `treat`, or other `food`.
  case catFed = "CatFed"
  /// A game with the cat (detail: the toy).
  case catPlayed = "CatPlayed"
  /// The cat was called over.
  case catCalled = "CatCalled"
  /// The cat did a trick it learned (detail: the trick).
  case trickDone = "TrickDone"
  /// A cat was chosen in the picker (detail: the cat).
  case catChosen = "CatChosen"
  /// The cat's temperament was shown to the user (detail: the temperament).
  case temperamentShown = "TemperamentShown"

  /// A note was opened, from the `widget` or in the `app`.
  case noteOpened = "NoteOpened"

  /// Decorating the room started.
  case decoratingOpened = "DecoratingOpened"
  /// A piece was put in the room (detail: the item).
  case roomItemPlaced = "RoomItemPlaced"
  /// A piece in the room was moved (detail: the item).
  case roomItemMoved = "RoomItemMoved"
  /// A piece was taken out of the room (detail: the item).
  case roomItemPutAway = "RoomItemPutAway"
  /// The room itself was changed: walls, floor, window (detail: what was changed).
  case roomCustomised = "RoomCustomised"

  /// The shop was opened.
  case shopOpened = "ShopOpened"
  /// An item was looked at in the shop (detail: the item).
  case shopItemViewed = "ShopItemViewed"
  /// An item was bought with stamps (detail: the item; value: its price in stamps).
  case shopItemBought = "ShopItemBought"

  /// The streak's flame scene was opened.
  case streakOpened = "StreakOpened"
  /// A streak milestone was shown (detail: the milestone).
  case streakMilestoneSeen = "StreakMilestoneSeen"

  /// A button on the widget was tapped: `pet` or `treat`.
  case widgetButtonTapped = "WidgetButtonTapped"

  /// The profile ("Us") was opened.
  case profileOpened = "ProfileOpened"
  /// The app asked the user to sign in with Apple.
  case signInPromptShown = "SignInPromptShown"
  /// The user answered that prompt: `accepted` or `dismissed`.
  case signInPromptAnswered = "SignInPromptAnswered"
}

/// What a name may carry besides itself, as `clientEventRules` in the contract says.
public struct ClientEventRule: Hashable, Sendable {
  public enum Detail: Hashable, Sendable {
    /// No detail.
    case none
    /// A catalogue id: see ``ClientEvent/isDetail(_:)``.
    case id
    /// One of these words.
    case oneOf([String])
  }

  public let detail: Detail
  /// The detail must be there.
  public let required: Bool
  /// It may carry a whole number from 0 to ``ClientEvent/maxValue``.
  public let value: Bool

  public init(detail: Detail, required: Bool = false, value: Bool = false) {
    self.detail = detail
    self.required = required
    self.value = value
  }
}

extension ClientEventName {
  public var rule: ClientEventRule {
    switch self {
    case .appOpened, .openingWatched, .openingSkipped, .catPetted, .catCalled, .decoratingOpened,
      .shopOpened, .streakOpened, .profileOpened, .signInPromptShown:
      ClientEventRule(detail: .none)
    case .widgetAdded, .catPlayed, .roomCustomised:
      ClientEventRule(detail: .id)
    case .trickDone, .catChosen, .temperamentShown, .roomItemPlaced, .roomItemMoved,
      .roomItemPutAway, .shopItemViewed, .streakMilestoneSeen:
      ClientEventRule(detail: .id, required: true)
    case .shopItemBought:
      ClientEventRule(detail: .id, required: true, value: true)
    case .catFed:
      ClientEventRule(detail: .oneOf(["treat", "food"]), required: true)
    case .noteOpened:
      ClientEventRule(detail: .oneOf(["widget", "app"]), required: true)
    case .widgetButtonTapped:
      ClientEventRule(detail: .oneOf(["pet", "treat"]), required: true)
    case .signInPromptAnswered:
      ClientEventRule(detail: .oneOf(["accepted", "dismissed"]), required: true)
    }
  }
}

/// One event with what it carries. Sent as an object; its name's ``ClientEventName/rule`` says
/// what is allowed, and a decoded one that breaks it is refused.
public struct ClientEvent: Codable, Hashable, Sendable {
  public let name: ClientEventName
  public let detail: String?
  public let value: Int?

  /// The most ``value`` may be. Only a price uses it.
  public static let maxValue = 100_000
  /// The longest a detail may be.
  public static let maxDetailLength = 40

  public init(_ name: ClientEventName, detail: String? = nil, value: Int? = nil) {
    self.name = name
    self.detail = detail
    self.value = value
  }

  /// Why this event breaks its name's rule or the detail and value limits, or `nil` when it keeps
  /// them.
  public var problem: String? {
    let rule = name.rule
    if let detail {
      guard Self.isDetail(detail) else { return "\(name.rawValue) has a malformed detail" }
      switch rule.detail {
      case .none: return "\(name.rawValue) takes no detail"
      case .id: break
      case .oneOf(let words):
        guard words.contains(detail) else {
          return "\(name.rawValue) takes one of \(words.joined(separator: ", "))"
        }
      }
    } else if rule.required {
      return "\(name.rawValue) needs a detail"
    }
    if let value {
      guard rule.value else { return "\(name.rawValue) takes no value" }
      guard (0...Self.maxValue).contains(value) else {
        return "\(name.rawValue) has a value out of range"
      }
    }
    return nil
  }

  /// Whether `text` may be a detail: a letter, then letters, digits and hyphens, at most
  /// ``maxDetailLength`` in all.
  public static func isDetail(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    guard let first = scalars.first, scalars.count <= maxDetailLength, isLetter(first) else {
      return false
    }
    return scalars.dropFirst().allSatisfy { isLetter($0) || ("0"..."9").contains($0) || $0 == "-" }
  }

  /// `raw` as a detail: every character that may not be in one becomes a hyphen and the rest is
  /// cut to ``maxDetailLength``, so `Pet_Pose.v2` is `Pet-Pose-v2`. `nil` when it does not start
  /// with a letter.
  public static func detail(from raw: String) -> String? {
    let mapped = String(
      String.UnicodeScalarView(
        raw.unicodeScalars.prefix(maxDetailLength).map {
          isLetter($0) || ("0"..."9").contains($0) || $0 == "-" ? $0 : "-"
        }))
    return isDetail(mapped) ? mapped : nil
  }

  private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
    ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(ClientEventName.self, forKey: .name)
    detail = try container.decodeIfPresent(String.self, forKey: .detail)
    value = try container.decodeIfPresent(Int.self, forKey: .value)
    if let problem {
      throw DecodingError.dataCorruptedError(
        forKey: .name, in: container, debugDescription: problem)
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encodeIfPresent(detail, forKey: .detail)
    try container.encodeIfPresent(value, forKey: .value)
  }

  private enum CodingKeys: String, CodingKey {
    case name
    case detail
    case value
  }
}

/// One reported event as it travels: a bare name, as builds before the detailed events send it,
/// or a ``ClientEvent``. Both mean the same when there is no detail. Each keeps its form when
/// encoded again.
public enum ReportedEvent: Codable, Hashable, Sendable {
  case name(ClientEventName)
  case event(ClientEvent)

  public var clientEvent: ClientEvent {
    switch self {
    case .name(let name): ClientEvent(name)
    case .event(let event): event
    }
  }

  public init(from decoder: any Decoder) throws {
    let single = try decoder.singleValueContainer()
    if let name = try? single.decode(ClientEventName.self) {
      self = .name(name)
    } else {
      self = .event(try single.decode(ClientEvent.self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var single = encoder.singleValueContainer()
    switch self {
    case .name(let name): try single.encode(name)
    case .event(let event): try single.encode(event)
    }
  }
}

public struct ReportEventsRequest: Codable, Hashable, Sendable {
  /// At most `ReportEventsRequest.maxEvents`.
  public let events: [ReportedEvent]

  public static let maxEvents = 20

  /// The request this build sends: every event as an object.
  public init(events: [ClientEvent]) {
    self.events = events.map(ReportedEvent.event)
  }

  public init(reported events: [ReportedEvent]) {
    self.events = events
  }

  /// Every event in either form, as a ``ClientEvent``.
  public var clientEvents: [ClientEvent] { events.map(\.clientEvent) }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let events = try container.decode([ReportedEvent].self, forKey: .events)
    guard events.count <= Self.maxEvents else {
      throw DecodingError.dataCorruptedError(
        forKey: .events, in: container,
        debugDescription: "at most \(Self.maxEvents) events per request")
    }
    self.events = events
  }

  private enum CodingKeys: String, CodingKey {
    case events
  }
}
