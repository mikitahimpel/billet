import Foundation
import Synchronization
import Testing
@testable import Billet

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
