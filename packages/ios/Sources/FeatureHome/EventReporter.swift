import Foundation
import Persistence
import Transport
import Wire

/// The names waiting to be sent. Names only: nothing else about the user or the app is kept.
struct EventOutbox: Codable, Equatable, Sendable {
  /// The most kept. When a phone has been offline for long the oldest are dropped.
  static let limit = 100

  private(set) var waiting: [ClientEventName] = []

  mutating func add(_ name: ClientEventName) {
    waiting.append(name)
    if waiting.count > Self.limit { waiting.removeFirst(waiting.count - Self.limit) }
  }

  /// The next request's worth.
  var batch: [ClientEventName] { Array(waiting.prefix(ReportEventsRequest.maxEvents)) }

  mutating func sent(_ count: Int) { waiting.removeFirst(min(count, waiting.count)) }
}

/// Counts what the app does, for the funnel in `docs/experiments.md`: it opened, a widget was
/// added. The opening's two names exist in `ClientEventName` but have no producer until the real
/// client has an opening. Only the names in `ClientEventName`; the server
/// stamps the time and adds the pair.
///
/// Reporting never blocks the app and never fails visibly. An event waits in a small file until it
/// can be sent, and a request that fails leaves it there for the next time.
@MainActor
final class EventReporter {
  private static let outboxName = "pending-events.json"
  private static let onceName = "reported-once.json"

  private let api: APIClient
  private let storage: AppGroupStorage?
  private var outbox: EventOutbox
  private var once: Set<String>
  private var opened = false
  private var flushing = false

  init(api: APIClient, storage: AppGroupStorage?) {
    self.api = api
    self.storage = storage
    outbox = (try? storage?.readJSON(EventOutbox.self, named: Self.outboxName)) ?? EventOutbox()
    once = (try? storage?.readJSON(Set<String>.self, named: Self.onceName)) ?? []
  }

  var waiting: [ClientEventName] { outbox.waiting }

  /// The app came to the front. Counted once for each launch.
  func appOpened() {
    guard !opened else { return }
    opened = true
    report(.appOpened)
  }

  /// This phone has a widget. Counted once for as long as the app is installed.
  func widgetAdded() { reportOnce(.widgetAdded) }

  private func reportOnce(_ name: ClientEventName) {
    guard once.insert(name.rawValue).inserted else { return }
    try? storage?.writeJSON(once, named: Self.onceName)
    report(name)
  }

  private func report(_ name: ClientEventName) {
    outbox.add(name)
    save()
  }

  /// Sends what is waiting, a request's worth at a time, and stops at the first failure.
  func flush() async {
    guard !flushing else { return }
    flushing = true
    defer { flushing = false }
    while !outbox.batch.isEmpty {
      let batch = outbox.batch
      do {
        try await api.reportEvents(batch)
      } catch {
        return
      }
      outbox.sent(batch.count)
      save()
    }
  }

  /// Forgets what is waiting and what was reported once, for sign-out: they belong to the account.
  func discard() {
    outbox = EventOutbox()
    once = []
    opened = false
    save()
    try? storage?.writeJSON(once, named: Self.onceName)
  }

  private func save() {
    try? storage?.writeJSON(outbox, named: Self.outboxName)
  }
}
