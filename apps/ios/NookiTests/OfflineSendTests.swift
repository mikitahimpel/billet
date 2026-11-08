import Foundation
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

/// The pair's journal as the outbox meets it: what it took, and whether it can be reached.
private nonisolated final class FakeJournal: Sendable {
    let taken = Mutex<[RecordCatEventRequest]>([])
    let failure = Mutex<TransportError?>(nil)

    var client: CatEventsClient {
        CatEventsClient(record: { (request) async throws(TransportError) in
            if let failure = self.failure.withLock({ $0 }) { throw failure }
            self.taken.withLock { $0.append(request) }
            // Taken: an answer the outbox reads as the server having it, without building the cat it returns.
            throw .decoding
        })
    }
}

@MainActor
@Suite struct CatEventOutboxTests {
    private let file = URL.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)/cat-events.json")

    @Test func sendsAtOnceWhenTheServerIsThere() async {
        let journal = FakeJournal()
        let outbox = CatEventOutbox(client: journal.client, file: file)
        await outbox.send([.petted, .fed(grams: 40)])
        #expect(journal.taken.withLock { $0.map(\.event) } == [.petted, .fed(grams: 40)])
        #expect(outbox.pending.isEmpty)
    }

    @Test func keepsEventsAcrossLaunchesWhileOfflineAndReplaysThemUnderTheSameKeys() async {
        let journal = FakeJournal()
        journal.failure.withLock { $0 = .network("offline") }
        let outbox = CatEventOutbox(client: journal.client, file: file)
        await outbox.send([.petted])
        await outbox.send([.fed(grams: 40)])
        #expect(await outbox.flush())
        let kept = outbox.pending
        #expect(kept.map(\.event) == [.petted, .fed(grams: 40)])

        journal.failure.withLock { $0 = nil }
        let relaunched = CatEventOutbox(client: journal.client, file: file)
        #expect(relaunched.pending == kept)
        #expect(await relaunched.flush() == false)
        #expect(journal.taken.withLock { $0 } == kept)
        #expect(CatEventOutbox(client: journal.client, file: file).pending.isEmpty)
    }

    @Test func dropsWhatTheServerRefusesAndKeepsWhatItCouldNotTake() async {
        let journal = FakeJournal()
        journal.failure.withLock { $0 = .api(.invalidRequest) }
        let outbox = CatEventOutbox(client: journal.client, file: file)
        await outbox.send([.petted])
        #expect(outbox.pending.isEmpty)

        for failure: TransportError in [.status(503), .network("lost"), .api(.unauthorized)] {
            journal.failure.withLock { $0 = failure }
            await outbox.send([.fed(grams: 40)])
            #expect(await outbox.flush(), "\(failure)")
        }
        #expect(outbox.pending.count == 3)
    }

    @Test func keepsOnlyTheNewestPastTheLimit() async {
        let journal = FakeJournal()
        journal.failure.withLock { $0 = .network("offline") }
        let outbox = CatEventOutbox(client: journal.client, file: file)
        await outbox.send(Array(repeating: .petted, count: CatEventOutbox.limit))
        await outbox.send([.fed(grams: 40)])
        #expect(outbox.pending.count == CatEventOutbox.limit)
        #expect(outbox.pending.last?.event == .fed(grams: 40))
    }
}

@MainActor
@Suite struct ResendTests {
    @Test func backsOffByDoublingUpToTheCeiling() {
        let resend = Resend(first: .seconds(2), ceiling: .seconds(60))
        #expect((1...7).map { resend.delay(after: $0) } == [2, 4, 8, 16, 32, 60, 60].map { .seconds($0) })
    }

    @Test func triesAgainUntilNothingWaits() async {
        let slept = Mutex<[Duration]>([])
        let resend = Resend(sleep: { delay in slept.withLock { $0.append(delay) } })
        var attempts = 0
        await resend.run {
            attempts += 1
            return attempts < 4
        }
        #expect(attempts == 4)
        #expect(slept.withLock { $0 } == [.seconds(2), .seconds(4), .seconds(8)])
    }

    @Test func stopsWhenItsTaskIsCancelled() async {
        let resend = Resend(sleep: { _ in throw CancellationError() })
        var attempts = 0
        await resend.run {
            attempts += 1
            return true
        }
        #expect(attempts == 1)
    }
}
