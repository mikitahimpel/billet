import FeaturePairing
import Foundation
import Persistence
import Synchronization
import Testing
import Transport
import WidgetInterface
import Wire
@testable import Billet

struct PairingCopyTests {
    @Test func aCodeReadsInGroupsOfFive() {
        #expect(PairingCopy.spaced("K7QM4R2XHP") == "K7QM4 R2XHP")
        #expect(PairingCopy.spaced("ABCDEFGH") == "ABCDE FGH")
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

    @Test func theInviteSendsTheLinkOfTheServerTheAppIsBuiltForAndTheCode() {
        let server = URL(string: "https://ourio-api-dev.example.dev")!
        #expect(PairingCopy.invite(code: "K7QM4R2XHP", server: server)
            == "Join me in Ourio! https://ourio-api-dev.example.dev/i/K7QM4R2XHP or enter my code: K7QM4R2XHP")
        let link = Backend.baseURL(host: "ourio-api.example.dev").map { InviteCode("K7QM4R2XHP").link(on: $0) }
        #expect(link.flatMap(DeepLink.init(url:)) == .invite("K7QM4R2XHP"))
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
        let record: Mutex<AccountRecord>

        init(paired: Bool = false, pairID: String? = nil) {
            record = Mutex(AccountRecord(userID: "u1", deviceID: "d1", expiresAt: .max, isPaired: paired, pairID: pairID))
        }

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
        #expect(session.pairing.state == .paired(.joiner(pairID: "p1")))

        session.pairingFinished()
        #expect(session.isPaired)
        #expect(saved.record.withLock { $0.isPaired && $0.pairID == "p1" })
        // The next pairing starts from the choice again.
        #expect(session.pairing.state == .initial)
        #expect(defaults.bool(forKey: CatLife.joinedKey))
    }

    private let defaults = UserDefaults(suiteName: "ServerSessionPairingTests-\(UUID().uuidString)")!

    /// The waits `watchPair` asked for, in order; each one returns at once.
    nonisolated final class Waits: Sendable {
        let list = Mutex<[Duration]>([])
    }

    /// `GET /v1/pair` throwing each of `errors` in turn, then answering with the pair.
    nonisolated final class PairAnswers: Sendable {
        let calls = Mutex(0)
        let errors: [TransportError]

        init(_ errors: [TransportError]) { self.errors = errors }

        var count: Int { calls.withLock { $0 } }

        func pair() throws(TransportError) -> PairResponse {
            let call = calls.withLock { count in
                count += 1
                return count
            }
            if call <= errors.count { throw errors[call - 1] }
            return PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
        }
    }

    private let waits = Waits()

    private func session(_ saved: Saved, api: APIClient) -> ServerSession {
        let backend = Backend(
            baseURL: URL(string: "https://api.example.dev")!, api: api, accounts: saved.store,
            keys: AccountKeyStore(loadOrCreate: { () throws(PersistenceError) in "key" },
                                  clear: { () throws(PersistenceError) in }))
        return ServerSession(backend: backend, defaults: defaults) { [waits] wait in
            waits.list.withLock { $0.append(wait) }
        }
    }

    /// An invite that runs out a day from now, in epoch milliseconds.
    private static let tomorrow = Int(Date.now.timeIntervalSince1970 * 1000) + 86_400_000

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
    }

    @Test func aPairFoundWithoutAShownInviteIsTheJoinersSoItAdoptsNoCat() async {
        let saved = Saved()
        var api = APIClient.offline
        api.pair = { () async throws(TransportError) in
            PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
        }
        let session = session(saved, api: api)
        await session.refreshPair()
        #expect(session.isPaired)
        #expect(defaults.bool(forKey: CatLife.joinedKey))
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

    @Test func aShownInviteIsCheckedEverySixSecondsUntilItsClaimEndsTheOpenPairing() async {
        let saved = Saved()
        let answers = PairAnswers([.api(.notFound), .api(.notFound)])
        var api = APIClient.offline
        let expiresAt = Self.tomorrow
        api.createInvite = { () async throws(TransportError) in
            CreateInviteResponse(code: InviteCode("ABC"), expiresAt: expiresAt)
        }
        api.pair = { () async throws(TransportError) in try answers.pair() }
        let session = session(saved, api: api)
        session.pairing.createInvite()
        await session.pairing.settled()
        let model = session.pairing
        await session.watchPair()
        #expect(session.isPaired)
        // The open sheet or invite page shows the pairing's own end.
        #expect(session.pairing === model)
        #expect(model.state == .paired(.inviter))
        // The phone that showed the code adopts the cat.
        #expect(!defaults.bool(forKey: CatLife.joinedKey))
        #expect(answers.count == 3)
        #expect(waits.list.withLock { $0 } == [.seconds(6), .seconds(6)])
    }

    @Test func aPhoneWithNoInviteOutAsksOnceAndThenWaitsForTheNextReturn() async {
        let saved = Saved()
        let answers = PairAnswers(Array(repeating: .api(.notFound), count: 10))
        var api = APIClient.offline
        api.pair = { () async throws(TransportError) in try answers.pair() }
        let session = session(saved, api: api)
        await session.watchPair()
        #expect(!session.isPaired)
        #expect(answers.count == 1)
        #expect(waits.list.withLock { $0 }.isEmpty)
    }

    @Test func anInviteThatRanOutIsNotCheckedAgain() async {
        let saved = Saved()
        let answers = PairAnswers(Array(repeating: .api(.notFound), count: 10))
        var api = APIClient.offline
        api.createInvite = { () async throws(TransportError) in
            CreateInviteResponse(code: InviteCode("ABC"), expiresAt: 9)
        }
        api.pair = { () async throws(TransportError) in try answers.pair() }
        let session = session(saved, api: api)
        session.pairing.createInvite()
        await session.pairing.settled()
        await session.watchPair()
        #expect(!session.isPaired)
        #expect(answers.count == 1)
        #expect(waits.list.withLock { $0 }.isEmpty)
    }

    @Test func aRefusedCheckWaitsLongerEachTimeUpToAMinute() async {
        let saved = Saved()
        // A 429 arrives as `Unavailable`.
        let answers = PairAnswers(
            [.api(.notFound)] + Array(repeating: .api(.unavailable), count: 5) + [.api(.notFound)])
        var api = APIClient.offline
        let expiresAt = Self.tomorrow
        api.createInvite = { () async throws(TransportError) in
            CreateInviteResponse(code: InviteCode("ABC"), expiresAt: expiresAt)
        }
        api.pair = { () async throws(TransportError) in try answers.pair() }
        let session = session(saved, api: api)
        session.pairing.createInvite()
        await session.pairing.settled()
        await session.watchPair()
        #expect(session.isPaired)
        #expect(waits.list.withLock { $0 } == [6, 12, 24, 48, 60, 60, 6].map { .seconds($0) })
    }

    @Test func aRelaunchEndsAPairTheServerNoLongerHasWithItsCursors() async {
        // A launch builds the session from the saved record, which still says paired.
        let saved = Saved(paired: true, pairID: "p1")
        for key in ServerSession.pairCursorKeys { defaults.set(41, forKey: key) }
        CatLife.markJoined(in: defaults)
        var api = APIClient.offline
        api.pair = { () async throws(TransportError) in throw .network("offline") }
        let offline = session(saved, api: api)
        await offline.watchPair()
        #expect(offline.isPaired)

        api.pair = { () async throws(TransportError) in throw .api(.notFound) }
        let session = session(saved, api: api)
        #expect(session.isPaired)
        await session.watchPair()
        #expect(!session.isPaired)
        #expect(saved.record.withLock { !$0.isPaired })
        #expect(ServerSession.pairCursorKeys.allSatisfy { defaults.object(forKey: $0) == nil })
        #expect(!defaults.bool(forKey: CatLife.joinedKey))
    }

    @Test func aClaimTheServerCallsAlreadyPairedMakesThisPhoneTheJoiner() async {
        let saved = Saved(pairID: "p0")
        var api = APIClient.offline
        api.claimInvite = { (_) async throws(TransportError) in throw .api(.alreadyPaired) }
        api.pair = { () async throws(TransportError) in
            PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
        }
        let session = session(saved, api: api)
        session.pairing.submit(code: "ABCD")
        await session.pairing.settled()
        #expect(session.pairing.state == .paired(.joiner(pairID: nil)))
        session.pairingFinished()
        #expect(session.isPaired)
        #expect(defaults.bool(forKey: CatLife.joinedKey))
        #expect(saved.record.withLock { $0.pairID } == "p0")
        for _ in 0..<50 where saved.record.withLock({ $0.pairID }) != "p1" { await Task.yield() }
        #expect(saved.record.withLock { $0.pairID } == "p1")
    }

    @Test func anInviterTheServerCallsAlreadyPairedKeepsThePairIDItHad() async {
        let saved = Saved(pairID: "p0")
        var api = APIClient.offline
        api.createInvite = { () async throws(TransportError) in throw .api(.alreadyPaired) }
        let session = session(saved, api: api)
        session.pairing.createInvite()
        await session.pairing.settled()
        session.pairingFinished()
        #expect(session.isPaired)
        #expect(saved.record.withLock { $0.isPaired && $0.pairID == "p0" })
        #expect(!defaults.bool(forKey: CatLife.joinedKey))
    }

    @Test func deletingTheAccountEndsThePair() async throws {
        let saved = Saved(paired: true, pairID: "p1")
        var api = APIClient.offline
        api.deleteAccount = { (_) async throws(TransportError) in }
        let session = session(saved, api: api)
        try await session.deleteAccount()
        #expect(!session.isPaired)
    }
}
