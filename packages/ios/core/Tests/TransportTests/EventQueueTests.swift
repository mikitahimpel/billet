import Foundation
import Synchronization
import Testing
import Wire

@testable import Transport

@MainActor
@Suite struct EventQueueTests {
  /// Answers each batch with the next of `answers`, then with success, and keeps every batch.
  final class Server: Sendable {
    let batches = Mutex<[[ClientEvent]]>([])
    let answers: Mutex<[TransportError?]>

    init(_ answers: [TransportError?] = []) {
      self.answers = Mutex(answers)
    }

    var send: @Sendable ([ClientEvent]) async throws(TransportError) -> Void {
      { (batch) async throws(TransportError) in
        self.batches.withLock { $0.append(batch) }
        let answer = self.answers.withLock { $0.isEmpty ? nil : $0.removeFirst() }
        if let answer { throw answer }
      }
    }
  }

  final class Saved {
    var events: [ClientEvent] = []
  }

  private func queue(_ server: Server, saved: Saved = Saved(), from: [ClientEvent] = [])
    -> EventQueue
  {
    EventQueue(saved: from, delay: .seconds(3600), send: server.send) { saved.events = $0 }
  }

  @Test func eventsAreSentTwentyToARequest() async {
    let server = Server()
    let saved = Saved()
    let events = queue(server, saved: saved)
    for _ in 0..<45 { events.reporter(.catPetted) }
    await events.flush()
    #expect(server.batches.withLock { $0.map(\.count) } == [20, 20, 5])
    #expect(events.pending.isEmpty)
    #expect(saved.events.isEmpty)
  }

  @Test func theOldestAreDroppedPastAHundred() {
    let saved = Saved()
    let events = queue(Server(), saved: saved)
    events.reporter(.shopOpened)
    for _ in 0..<EventQueue.capacity { events.reporter(.catPetted) }
    #expect(events.pending.count == EventQueue.capacity)
    #expect(!events.pending.contains(ClientEvent(.shopOpened)))
    #expect(saved.events == events.pending)
  }

  @Test func aFailedRequestKeepsItsEventsForNextTime() async {
    let server = Server([.network("offline")])
    let events = queue(server)
    events.reporter(.catFed, detail: "treat")
    await events.flush()
    #expect(events.pending == [ClientEvent(.catFed, detail: "treat")])
    await events.flush()
    #expect(events.pending.isEmpty)
    #expect(server.batches.withLock { $0.count } == 2)
  }

  @Test func aRefusedBatchIsDroppedRatherThanRetried() async {
    let server = Server([.api(.invalidRequest)])
    let events = queue(server)
    events.reporter(.catPetted)
    await events.flush()
    #expect(events.pending.isEmpty)
  }

  @Test func waitingEventsSurviveARelaunch() async {
    let server = Server()
    let events = queue(server, from: [ClientEvent(.shopOpened)])
    await events.flush()
    #expect(server.batches.withLock { $0 } == [[ClientEvent(.shopOpened)]])
  }

  @Test(arguments: [
    ClientEvent(.shopItemViewed, detail: "my secret note"),
    ClientEvent(.shopItemViewed, detail: "Мой кот"),
    ClientEvent(.shopItemViewed, detail: "a@b.com"),
    ClientEvent(.shopItemViewed),
    ClientEvent(.catPetted, detail: "lamp"),
    ClientEvent(.catFed, detail: "cake"),
    ClientEvent(.shopOpened, value: 3),
    ClientEvent(.shopItemBought, detail: "lamp", value: -1),
  ])
  func anEventOutsideItsRuleNeverLeavesThePhone(_ event: ClientEvent) async {
    let server = Server()
    let events = queue(server, from: [event])
    events.reporter(event)
    await events.flush()
    #expect(events.pending.isEmpty)
    #expect(server.batches.withLock { $0.isEmpty })
  }

  @Test func forgettingDropsWhatWasWaiting() {
    let saved = Saved()
    let events = queue(Server([.network("offline")]), saved: saved)
    events.reporter(.catPetted)
    events.forget()
    #expect(events.pending.isEmpty)
    #expect(saved.events.isEmpty)
  }

  @Test func recordingSendsByItselfAfterTheDelay() async {
    let server = Server()
    let events = EventQueue(saved: [], delay: .milliseconds(10), send: server.send) { _ in }
    events.reporter(.profileOpened)
    for _ in 0..<200 where server.batches.withLock({ $0.isEmpty }) {
      try? await Task.sleep(for: .milliseconds(5))
    }
    #expect(server.batches.withLock { $0 } == [[ClientEvent(.profileOpened)]])
  }
}
