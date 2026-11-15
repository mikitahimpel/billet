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

    @Test(arguments: [
        (86_400, "Expires in 24 h"), (86_399, "Expires in 24 h"), (82_801, "Expires in 24 h"),
        (82_800, "Expires in 23 h"), (3_601, "Expires in 2 h"), (3_600, "Expires in 1 h"),
        (3_599, "Expires in 59:59"), (60, "Expires in 1:00"), (59, "Expires in 0:59"),
    ])
    func aDayLongCodeCountsInHoursUntilItsLastHour(left: Int, text: String) {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(PairingCopy.expiry(expiresAt: 1_000_000 + left * 1000, now: now) == text)
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
        let session = session(saved, api: api)
        #expect(!session.isPaired)

        session.pairing.submit(code: "abcd efgh")
        await session.pairing.settled()
        #expect(session.pairing.state == .paired(pairID: "p1"))

        session.pairingFinished()
        #expect(session.isPaired)
        #expect(saved.record.withLock { $0.isPaired && $0.pairID == "p1" })
        // The next pairing starts from the choice again.
        #expect(session.pairing.state == .initial)
        #expect(defaults.object(forKey: CatLife.joinedKey) is Date)
    }

    private let defaults = UserDefaults(suiteName: "ServerSessionPairingTests-\(UUID().uuidString)")!

    private func session(_ saved: Saved, api: APIClient) -> ServerSession {
        let backend = Backend(
            baseURL: URL(string: "https://api.example.dev")!, api: api, accounts: saved.store,
            keys: AccountKeyStore(loadOrCreate: { () throws(PersistenceError) in "key" },
                                  clear: { () throws(PersistenceError) in }))
        return ServerSession(backend: backend, defaults: defaults)
    }

    @Test func aPairMadeWhileTheAppWasClosedIsTakenFromTheServer() async {
        let saved = Saved()
        var api = APIClient.offline
        api.pair = { () async throws(TransportError) in
            PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
        }
        let session = session(saved, api: api)
        #expect(!session.isPaired)
        await session.watchPair()
        #expect(session.isPaired)
        #expect(saved.record.withLock { $0.isPaired && $0.pairID == "p1" })
        // The inviter's phone adopts the cat; only the one that entered the code waits for it.
        #expect(defaults.object(forKey: CatLife.joinedKey) == nil)
    }

    @Test func anUnpairedAccountStaysUnpairedAndAnOfflineOneKeepsItsRecord() async {
        let saved = Saved()
        var api = APIClient.offline
        api.pair = { () async throws(TransportError) in throw .api(.notFound) }
        let unpaired = session(saved, api: api)
        await unpaired.refreshPair()
        #expect(!unpaired.isPaired)
        api.pair = { () async throws(TransportError) in throw .network("offline") }
        let offline = session(saved, api: api)
        await offline.refreshPair()
        #expect(!offline.isPaired)
        #expect(saved.record.withLock { !$0.isPaired })
    }

    @Test func theServersPairLeavesAnOpenInviteToShowItsOwnEnd() async {
        let saved = Saved()
        let calls = Mutex(0)
        var api = APIClient.offline
        api.createInvite = { () async throws(TransportError) in
            CreateInviteResponse(code: InviteCode("ABC"), expiresAt: 9)
        }
        api.pair = { () async throws(TransportError) in
            let call = calls.withLock { count in
                count += 1
                return count
            }
            if call < 2 { throw .api(.notFound) }
            return PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
        }
        let session = session(saved, api: api)
        session.pairing.createInvite()
        await session.pairing.settled()
        let model = session.pairing
        await session.watchPair()
        #expect(session.isPaired)
        #expect(session.pairing === model)
        #expect(calls.withLock { $0 } == 2)
    }
}
