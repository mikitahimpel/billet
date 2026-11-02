import Foundation
import Persistence
import Testing
import Transport
import Wire

@testable import FeatureHome

@Suite @MainActor struct EventReporterTests {
  /// Records what the server was sent, and can be told to fail.
  final class Server: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[ClientEventName]] = []
    private var failing = false

    var sent: [[ClientEventName]] { lock.withLock { batches } }
    func setFailing(_ value: Bool) { lock.withLock { failing = value } }

    var api: APIClient {
      var client = APIClient.offline
      client.reportEvents = { [self] (events) async throws(TransportError) in
        let refused = lock.withLock { () -> Bool in
          if failing { return true }
          batches.append(events)
          return false
        }
        if refused { throw .network("offline") }
      }
      return client
    }
  }

  private func storage() -> AppGroupStorage {
    .directory(FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
  }

  @Test func theAppOpeningIsCountedOncePerLaunch() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.appOpened()
    reporter.appOpened()
    await reporter.flush()
    #expect(server.sent == [[.appOpened]])
  }

  @Test func aWidgetIsCountedOnceEvenAcrossLaunches() async {
    let server = Server()
    let storage = storage()
    let first = EventReporter(api: server.api, storage: storage)
    first.widgetAdded()
    first.widgetAdded()
    await first.flush()
    let second = EventReporter(api: server.api, storage: storage)
    second.widgetAdded()
    await second.flush()
    #expect(server.sent == [[.widgetAdded]])
  }

  @Test func whatCouldNotBeSentWaitsAndGoesLaterInOrder() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    server.setFailing(true)
    reporter.appOpened()
    reporter.widgetAdded()
    await reporter.flush()
    #expect(server.sent.isEmpty)
    #expect(reporter.waiting == [.appOpened, .widgetAdded])
    server.setFailing(false)
    await reporter.flush()
    #expect(server.sent == [[.appOpened, .widgetAdded]])
    #expect(reporter.waiting.isEmpty)
  }

  @Test func whatWaitsSurvivesARestart() async {
    let server = Server()
    let storage = storage()
    server.setFailing(true)
    let first = EventReporter(api: server.api, storage: storage)
    first.appOpened()
    await first.flush()
    server.setFailing(false)
    let second = EventReporter(api: server.api, storage: storage)
    await second.flush()
    #expect(server.sent == [[.appOpened]])
  }

  @Test func aSentEventIsNeverSentTwice() async {
    let server = Server()
    let reporter = EventReporter(api: server.api, storage: storage())
    reporter.appOpened()
    await reporter.flush()
    await reporter.flush()
    #expect(server.sent.count == 1)
  }

  @Test func aLongWaitIsSentInRequestsThatFit() async {
    var outbox = EventOutbox()
    for _ in 0..<45 { outbox.add(.appOpened) }
    var sizes: [Int] = []
    while !outbox.batch.isEmpty {
      sizes.append(outbox.batch.count)
      outbox.sent(outbox.batch.count)
    }
    #expect(sizes == [20, 20, 5])
  }

  @Test func theWaitingListIsCappedAndDropsTheOldest() {
    var outbox = EventOutbox()
    outbox.add(.widgetAdded)
    for _ in 0..<EventOutbox.limit { outbox.add(.appOpened) }
    #expect(outbox.waiting.count == EventOutbox.limit)
    #expect(!outbox.waiting.contains(.widgetAdded))
  }

  @Test func signingOutForgetsWhatWaitedAndWhatWasCountedOnce() async {
    let server = Server()
    let storage = storage()
    let reporter = EventReporter(api: server.api, storage: storage)
    server.setFailing(true)
    reporter.appOpened()
    reporter.widgetAdded()
    await reporter.flush()
    reporter.discard()
    server.setFailing(false)
    await reporter.flush()
    #expect(server.sent.isEmpty)
    reporter.widgetAdded()
    await reporter.flush()
    #expect(server.sent == [[.widgetAdded]])
  }

  @Test func onlyNamesAreStoredOnDevice() throws {
    let storage = storage()
    let reporter = EventReporter(api: Server().api, storage: storage)
    reporter.appOpened()
    let data = try #require(try storage.read("pending-events.json"))
    #expect(String(decoding: data, as: UTF8.self) == #"{"waiting":["AppOpened"]}"#)
  }
}
