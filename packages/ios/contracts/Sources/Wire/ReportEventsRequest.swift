/// Events the app may report about itself. No note, image, text or time: the server stamps the
/// time and pair, and records `InviteCreated`, `PairClaimed`, `NoteSent` and `AccountDeleted`
/// itself, so those are refused if sent.
public enum ClientEventName: String, Codable, Hashable, Sendable, CaseIterable {
  /// At most one per launch.
  case appOpened = "AppOpened"
  /// Once per widget kind.
  case widgetAdded = "WidgetAdded"
  case openingWatched = "OpeningWatched"
  case openingSkipped = "OpeningSkipped"

  case catPetted = "CatPetted"
  case catFed = "CatFed"
  case catPlayed = "CatPlayed"
  case catCalled = "CatCalled"
  case trickDone = "TrickDone"
  case catChosen = "CatChosen"
  case temperamentShown = "TemperamentShown"

  case noteOpened = "NoteOpened"

  case decoratingOpened = "DecoratingOpened"
  case roomItemPlaced = "RoomItemPlaced"
  case roomItemMoved = "RoomItemMoved"
  case roomItemPutAway = "RoomItemPutAway"
  case roomCustomised = "RoomCustomised"
  case roomOpened = "RoomOpened"

  case shopOpened = "ShopOpened"
  case shopItemViewed = "ShopItemViewed"
  /// value: its price in stamps.
  case shopItemBought = "ShopItemBought"
  case shopOfferViewed = "ShopOfferViewed"
  /// value: its price in stamps.
  case shopBundleBought = "ShopBundleBought"
  /// value: the stamps given back.
  case shopPurchaseUndone = "ShopPurchaseUndone"
  /// value: stamps.
  case shopDailyGiftClaimed = "ShopDailyGiftClaimed"
  /// value: its price in stamps.
  case shopGiftSent = "ShopGiftSent"

  case streakOpened = "StreakOpened"
  case streakMilestoneSeen = "StreakMilestoneSeen"

  case widgetButtonTapped = "WidgetButtonTapped"

  /// One per session.
  case pickTonightOpened = "PickTonightOpened"
  case pickTonightMatched = "PickTonightMatched"
  case pickTonightPlanned = "PickTonightPlanned"

  case profileOpened = "ProfileOpened"
  case signInPromptShown = "SignInPromptShown"
  case signInPromptAnswered = "SignInPromptAnswered"

  case onboardingStepViewed = "OnboardingStepViewed"
  /// Never the answer itself.
  case onboardingStepAnswered = "OnboardingStepAnswered"
  case onboardingStepSkipped = "OnboardingStepSkipped"
  /// Under 13. The age answer is never sent.
  case ageGateStopped = "AgeGateStopped"

  case tipShown = "TipShown"
  case tipDismissed = "TipDismissed"
  /// The hint's thing was done, or its button tapped.
  case tipAction = "TipAction"
}

public struct ClientEventRule: Hashable, Sendable {
  public enum Detail: Hashable, Sendable {
    case none
    case id
    case oneOf([String])
  }

  public let detail: Detail
  public let required: Bool
  /// A whole number from 0 to ``ClientEvent/maxValue``.
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
      .shopOpened, .streakOpened, .profileOpened, .signInPromptShown, .ageGateStopped,
      .pickTonightOpened, .pickTonightMatched, .pickTonightPlanned:
      ClientEventRule(detail: .none)
    case .widgetAdded, .catPlayed, .roomCustomised:
      ClientEventRule(detail: .id)
    case .trickDone, .catChosen, .temperamentShown, .roomItemPlaced, .roomItemMoved,
      .roomItemPutAway, .shopItemViewed, .shopOfferViewed, .streakMilestoneSeen,
      .onboardingStepViewed, .onboardingStepAnswered, .onboardingStepSkipped, .tipShown,
      .tipDismissed, .tipAction:
      ClientEventRule(detail: .id, required: true)
    case .shopItemBought, .shopBundleBought, .shopPurchaseUndone, .shopDailyGiftClaimed,
      .shopGiftSent:
      ClientEventRule(detail: .id, required: true, value: true)
    case .catFed:
      ClientEventRule(detail: .oneOf(["treat", "food"]), required: true)
    case .noteOpened:
      ClientEventRule(detail: .oneOf(["widget", "app"]), required: true)
    case .roomOpened:
      ClientEventRule(detail: .oneOf(["room", "city"]), required: true)
    case .widgetButtonTapped:
      ClientEventRule(detail: .oneOf(["pet", "treat"]), required: true)
    case .signInPromptAnswered:
      ClientEventRule(detail: .oneOf(["accepted", "dismissed"]), required: true)
    }
  }
}

/// A decoded event that breaks its name's ``ClientEventName/rule`` is refused.
public struct ClientEvent: Codable, Hashable, Sendable {
  public let name: ClientEventName
  public let detail: String?
  public let value: Int?

  public static let maxValue = 100_000
  public static let maxDetailLength = 40

  public init(_ name: ClientEventName, detail: String? = nil, value: Int? = nil) {
    self.name = name
    self.detail = detail
    self.value = value
  }

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

  public static func isDetail(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    guard let first = scalars.first, scalars.count <= maxDetailLength, isLetter(first) else {
      return false
    }
    return scalars.dropFirst().allSatisfy { isLetter($0) || ("0"..."9").contains($0) || $0 == "-" }
  }

  /// Disallowed characters become hyphens, cut to ``maxDetailLength``: `Pet_Pose.v2` is
  /// `Pet-Pose-v2`. `nil` when it does not start with a letter.
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

/// A bare name, as older builds send it, or a ``ClientEvent``; equal when there is no detail.
/// Each keeps its form when encoded again.
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
  public let events: [ReportedEvent]

  public static let maxEvents = 20

  public init(events: [ClientEvent]) {
    self.events = events.map(ReportedEvent.event)
  }

  public init(reported events: [ReportedEvent]) {
    self.events = events
  }

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
