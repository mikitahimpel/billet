import Foundation
import Persistence
import Pet
import Transport
import Wire

/// The events waiting to be sent. Each is a name with at most a catalogue id and a price: nothing
/// else about the user or the app is kept.
struct EventOutbox: Codable, Equatable, Sendable {
  /// The most kept. When a phone has been offline for long the oldest are dropped.
  static let limit = 100

  private(set) var waiting: [ClientEvent] = []

  init() {}

  /// Reads a saved outbox in either form an event is sent in, so one saved as bare names by an
  /// earlier build is still sent.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    waiting = try container.decode([ReportedEvent].self, forKey: .waiting).map(\.clientEvent)
  }

  mutating func add(_ event: ClientEvent) {
    waiting.append(event)
    if waiting.count > Self.limit { waiting.removeFirst(waiting.count - Self.limit) }
  }

  /// The next request's worth.
  var batch: [ClientEvent] { Array(waiting.prefix(ReportEventsRequest.maxEvents)) }

  mutating func sent(_ count: Int) { waiting.removeFirst(min(count, waiting.count)) }

  private enum CodingKeys: String, CodingKey {
    case waiting
  }
}

/// Counts what the app does, for the funnel in `docs/experiments.md`: it opened, a widget was
/// added, and what the user did with the cat, the room, the shop and the streak (``AppEvent``).
/// Only the events of `ClientEventName`, each with what its rule allows; the server stamps the time
/// and adds the pair.
///
/// Reporting never blocks the app and never fails visibly. An event waits in a small file until it
/// can be sent, and a request that fails leaves it there for the next time, unless the server
/// refused it as malformed, which no retry would change.
///
/// The service status can switch reporting off. While it is off nothing is recorded, what was
/// waiting is dropped, and nothing is sent.
@MainActor
final class EventReporter {
  private static let outboxName = "pending-events.json"
  private static let onceName = "reported-once.json"
  /// The same event again within this long counts once, for those a single gesture can repeat.
  static let repeatGap: TimeInterval = 10

  private let api: APIClient
  private let storage: AppGroupStorage?
  private let isEnabled: @MainActor () -> Bool
  private let now: () -> Date
  private var outbox: EventOutbox
  private var once: Set<String>
  private var lastRepeatable: [ClientEvent: Date] = [:]
  private var opened = false
  private var flushing = false

  init(
    api: APIClient, storage: AppGroupStorage?,
    isEnabled: @escaping @MainActor () -> Bool = { true },
    now: @escaping () -> Date = Date.init
  ) {
    self.api = api
    self.storage = storage
    self.isEnabled = isEnabled
    self.now = now
    outbox = (try? storage?.readJSON(EventOutbox.self, named: Self.outboxName)) ?? EventOutbox()
    once = (try? storage?.readJSON(Set<String>.self, named: Self.onceName)) ?? []
  }

  var waiting: [ClientEvent] { outbox.waiting }

  /// The app came to the front. Counted once for each launch.
  func appOpened() {
    guard !opened, isOn() else { return }
    opened = true
    report(ClientEvent(.appOpened))
  }

  /// This phone has widgets of `kinds`. Each kind is counted once for as long as the app is
  /// installed. A kind that cannot be a detail is counted as a widget of no kind.
  func widgetsAdded(kinds: Set<String>) {
    for kind in kinds.sorted() {
      reportOnce(ClientEvent(.widgetAdded, detail: ClientEvent.detail(from: kind)))
    }
  }

  /// Something the user did, from the views.
  func record(_ event: AppEvent) {
    let event = ClientEvent(reporting: event)
    guard Self.repeatable.contains(event.name) else {
      report(event)
      return
    }
    let at = now()
    if let last = lastRepeatable[event], at.timeIntervalSince(last) < Self.repeatGap { return }
    lastRepeatable[event] = at
    report(event)
  }

  /// Events one gesture can send many of: taps and strokes on the cat, games, picks in the shop
  /// and drags in the room.
  private static let repeatable: Set<ClientEventName> = [
    .catPetted, .catPlayed, .shopItemViewed, .roomItemMoved,
  ]

  private func reportOnce(_ event: ClientEvent) {
    guard isOn() else { return }
    let key = [event.name.rawValue, event.detail].compactMap { $0 }.joined(separator: ":")
    guard once.insert(key).inserted else { return }
    try? storage?.writeJSON(once, named: Self.onceName)
    report(event)
  }

  private func report(_ event: ClientEvent) {
    guard event.problem == nil, isOn() else { return }
    outbox.add(event)
    save()
  }

  /// Sends what is waiting, a request's worth at a time. A request the server refused as malformed
  /// is dropped; any other failure stops, and what is left waits for the next time.
  func flush() async {
    guard !flushing, isOn() else { return }
    flushing = true
    defer { flushing = false }
    while !outbox.batch.isEmpty {
      let batch = outbox.batch
      do throws(TransportError) {
        try await api.reportEvents(batch)
      } catch {
        guard Self.isRefusal(error) else { return }
      }
      outbox.sent(batch.count)
      save()
    }
  }

  /// Drops what is waiting when the service has switched reporting off.
  func analyticsChanged() {
    _ = isOn()
  }

  /// Whether reporting is on. When it is off, what was waiting is dropped.
  private func isOn() -> Bool {
    guard isEnabled() else {
      if !outbox.waiting.isEmpty {
        outbox = EventOutbox()
        save()
      }
      return false
    }
    return true
  }

  /// A 400: the server will never take this request, so sending it again would only hold up
  /// the ones after it.
  private static func isRefusal(_ error: TransportError) -> Bool {
    switch error {
    case .api(.invalidRequest), .status(400): true
    case .network, .api, .status, .maintenance, .encoding, .decoding: false
    }
  }

  /// Forgets what is waiting and what was reported once, for sign-out: they belong to the account.
  func discard() {
    outbox = EventOutbox()
    once = []
    opened = false
    lastRepeatable = [:]
    save()
    try? storage?.writeJSON(once, named: Self.onceName)
  }

  private func save() {
    try? storage?.writeJSON(outbox, named: Self.outboxName)
  }
}

extension ClientEvent {
  /// The event `event` is reported as. Every id is a catalogue id the app ships; ``AppEvent``
  /// says which.
  init(reporting event: AppEvent) {
    switch event {
    case .catPetted: self.init(.catPetted)
    case .catFed(.treat): self.init(.catFed, detail: "treat")
    case .catFed(.food): self.init(.catFed, detail: "food")
    case .catPlayed(let toy): self.init(.catPlayed, detail: toy?.rawValue)
    case .catCalled: self.init(.catCalled)
    case .trickDone(let trick): self.init(.trickDone, detail: trick.rawValue)
    case .catChosen(let cat): self.init(.catChosen, detail: cat.rawValue)
    case .temperamentShown(let temperament):
      self.init(.temperamentShown, detail: temperament.rawValue)
    case .noteOpened(.widget): self.init(.noteOpened, detail: "widget")
    case .noteOpened(.app): self.init(.noteOpened, detail: "app")
    case .decoratingOpened: self.init(.decoratingOpened)
    case .roomItemPlaced(let item): self.init(.roomItemPlaced, detail: item)
    case .roomItemMoved(let item): self.init(.roomItemMoved, detail: item)
    case .roomItemPutAway(let item): self.init(.roomItemPutAway, detail: item)
    case .roomCustomised(let change): self.init(.roomCustomised, detail: change)
    case .shopOpened: self.init(.shopOpened)
    case .shopItemViewed(let item): self.init(.shopItemViewed, detail: item)
    case .shopItemBought(let item, let price):
      self.init(.shopItemBought, detail: item, value: price)
    case .shopOfferViewed(let offer): self.init(.shopOfferViewed, detail: offer)
    case .shopBundleBought(let bundle, let price):
      self.init(.shopBundleBought, detail: bundle, value: price)
    case .shopPurchaseUndone(let id, let stamps):
      self.init(.shopPurchaseUndone, detail: id, value: stamps)
    case .shopDailyGiftClaimed(.stamps(let stamps)):
      self.init(.shopDailyGiftClaimed, detail: "stamps", value: stamps)
    case .shopDailyGiftClaimed(.item(let item)):
      self.init(.shopDailyGiftClaimed, detail: item, value: 0)
    case .shopGiftSent(let item, let price):
      self.init(.shopGiftSent, detail: item, value: price)
    case .streakOpened: self.init(.streakOpened)
    case .streakMilestoneSeen(let stage): self.init(.streakMilestoneSeen, detail: stage.eventID)
    case .widgetButtonTapped(.pet): self.init(.widgetButtonTapped, detail: "pet")
    case .widgetButtonTapped(.treat): self.init(.widgetButtonTapped, detail: "treat")
    case .profileOpened: self.init(.profileOpened)
    case .signInPromptShown: self.init(.signInPromptShown)
    case .signInPromptAnswered(let accepted):
      self.init(.signInPromptAnswered, detail: accepted ? "accepted" : "dismissed")
    }
  }
}

extension FlameStage {
  /// The stage's name, as a detail.
  var eventID: String {
    switch self {
    case .ember: "ember"
    case .spark: "spark"
    case .candle: "candle"
    case .steady: "steady"
    case .lantern: "lantern"
    case .hearth: "hearth"
    case .fire: "fire"
    case .beacon: "beacon"
    case .everglow: "everglow"
    }
  }
}
