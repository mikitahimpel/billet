import FeaturePairing
import Foundation
import Persistence
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

struct PairingCopyTests {
    @Test func aCodeReadsInGroupsOfFour() {
        #expect(PairingCopy.spaced("ABCDEFGH") == "ABCD EFGH")
        #expect(PairingCopy.spaced("ABC") == "ABC")
        #expect(PairingCopy.spaced("") == "")
    }

    @Test func theExpiryCountsDownAndThenSaysSo() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(PairingCopy.expiry(expiresAt: 1_000_000 + 581_000, now: now) == "Expires in 9:41")
        #expect(PairingCopy.expiry(expiresAt: 1_000_000 + 5_000, now: now) == "Expires in 0:05")
        #expect(PairingCopy.expiry(expiresAt: 1_000_000, now: now) == "This code has expired")
    }

    @Test func everyFailureSaysOurioNotBillet() {
        for failure in [PairingFailure.invalidCode, .alreadyPaired, .signedOut, .unavailable] {
            #expect(!PairingCopy.message(for: failure).contains("Billet"))
        }
    }
}

@MainActor
struct ServerSessionPairingTests {
    /// An account store in memory, signed in and unpaired.
    final class Saved: Sendable {
        let record = Mutex(AccountRecord(userID: "u1", deviceID: "d1", expiresAt: .max))

        var store: AccountStore {
            AccountStore(
                load: { [self] () throws(PersistenceError) in ("token", record.withLock { $0 }) },
                save: { [self] (_, new) throws(PersistenceError) in record.withLock { $0 = new } },
                setPaired: { [self] (paired, pairID) throws(PersistenceError) in
                    record.withLock {
                        $0.isPaired = paired
                        $0.pairID = pairID
                    }
                },
                clear: { () throws(PersistenceError) in })
        }
    }

    @Test func enteringTheCodeSavesThePairOnThisPhone() async {
        let saved = Saved()
        var api = APIClient.offline
        api.claimInvite = { (_) async throws(TransportError) in ClaimInviteResponse(pairId: PairId("p1")) }
        let backend = Backend(
            baseURL: URL(string: "https://api.example.dev")!, api: api, accounts: saved.store,
            keys: AccountKeyStore(loadOrCreate: { () throws(PersistenceError) in "key" },
                                  clear: { () throws(PersistenceError) in }))
        let session = ServerSession(backend: backend)
        #expect(!session.isPaired)

        session.pairing.submit(code: "abcd efgh")
        await session.pairing.settled()
        #expect(session.pairing.state == .paired(pairID: "p1"))

        session.pairingFinished()
        #expect(session.isPaired)
        #expect(saved.record.withLock { $0.isPaired && $0.pairID == "p1" })
        // The next pairing starts from the choice again.
        #expect(session.pairing.state == .initial)
    }
}
