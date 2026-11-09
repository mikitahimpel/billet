import Foundation
import Pet
import RoomInterface
import Synchronization
import Testing
import Transport
import Wire
@testable import Billet

/// The pair's cat as its room keeps it: the profile, the journal, and whether it can be reached.
private nonisolated final class FakeCatRoom: Sendable {
    struct State {
        var profile: Wire.CatProfile?
        var entries: [CatEntry] = []
        var online = true
        /// What the room answers a recorded event with instead of storing it.
        var refusal: TransportError?
        var adoptions: [SaveCatRequest] = []
        var records: [RecordCatEventRequest] = []
        var now = 1_800_000_000_000
    }

    let state: Mutex<State>
    let caller: String

    init(profile: Wire.CatProfile? = nil, entries: [CatEntry] = [], caller: String = "user-me") {
        state = Mutex(State(profile: profile, entries: entries))
        self.caller = caller
    }

    func set(online: Bool) { state.withLock { $0.online = online } }

    /// The partner did something: the room stores it, as their phone's record would.
    @discardableResult
    func partner(_ event: CatEvent, by user: String = "user-them") -> CatEntry {
        state.withLock { state in
            let entry = CatEntry(seq: state.entries.count + 1, id: .make(), by: UserId(user), at: state.now, event: event)
            state.entries.append(entry)
            return entry
        }
    }

    private func response(_ state: State) -> CatResponse {
        CatResponse(cat: state.profile, temper: CatTemper(curious: 0.5, lazy: 0.5, cuddly: 0.5),
                    needs: CatNeeds(at: state.now, full: 1, rested: 1, loved: 1, playful: 1, mood: 1, asleep: false),
                    lastSeq: state.entries.count)
    }

    var client: CatEventsClient {
        CatEventsClient(
            record: { (request) async throws(TransportError) in
                try self.state.withLock { (state) throws(TransportError) in
                    guard state.online else { throw .network("offline") }
                    if let refusal = state.refusal { throw refusal }
                    state.records.append(request)
                    if let earlier = state.entries.first(where: { $0.id == request.id }) {
                        return RecordCatEventResponse(entry: earlier, temper: self.response(state).temper,
                                                      needs: self.response(state).needs)
                    }
                    let entry = CatEntry(seq: state.entries.count + 1, id: request.id, by: UserId(self.caller),
                                         at: state.now, event: request.event)
                    state.entries.append(entry)
                    return RecordCatEventResponse(entry: entry, temper: self.response(state).temper,
                                                  needs: self.response(state).needs)
                }
            },
            load: { () async throws(TransportError) in
                try self.state.withLock { (state) throws(TransportError) in
                    guard state.online else { throw .network("offline") }
                    return self.response(state)
                }
            },
            adopt: { (request) async throws(TransportError) in
                try self.state.withLock { (state) throws(TransportError) in
                    guard state.online else { throw .network("offline") }
                    state.adoptions.append(request)
                    state.profile = state.profile ?? Wire.CatProfile(
                        name: request.name, look: request.look, bornAt: state.now, natureSeed: "424242",
                        utcOffsetSeconds: request.utcOffsetSeconds)
                    return self.response(state)
                }
            },
            journal: { (after) async throws(TransportError) in
                try self.state.withLock { (state) throws(TransportError) in
                    guard state.online else { throw .network("offline") }
                    return Array(state.entries.filter { $0.seq > after }.prefix(CatEventsClient.journalPage))
                }
            })
    }
}

private let pair = CatPair(me: "user-me", partner: "user-them")
private let profile = Wire.CatProfile(
    name: "Pancake", look: CatLook(model: "mochi", coat: "ginger"), bornAt: 1_799_000_000_000,
    natureSeed: "987654321", utcOffsetSeconds: 3600)

@MainActor
@Suite struct CatLifeTests {
    private let defaults: UserDefaults
    private let formerOutbox = URL.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)/cat-events.json")

    init() {
        defaults = UserDefaults(suiteName: "CatLifeTests-\(UUID().uuidString)")!
    }

    private func life() -> CatLife {
        CatLife(defaults: defaults, formerOutbox: formerOutbox, catName: { "Pancake" }, catCoat: { "ginger" })
    }

    /// Lets the outbox's own task run.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func bothPhonesRaiseTheRoomsCatFromItsSeedAndBirth() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        var changes: [CatLifeChange] = []
        life.observe { changes.append($0); return true }

        await life.connect(room.client, pair: pair)

        #expect(life.seed == 987_654_321)
        #expect(life.context.born == Date(timeIntervalSince1970: 1_799_000_000))
        #expect(life.context.utcOffset == 3600)
        #expect(life.context.partners == ["user-me", "user-them"])
        #expect(life.me == "user-me")
        #expect(changes.contains { if case .reset = $0 { true } else { false } })
        #expect(room.state.withLock { $0.adoptions }.isEmpty)
    }

    @Test func thePhoneThatFindsNoCatAdoptsHer() async {
        let room = FakeCatRoom()
        let life = life()
        await life.connect(room.client, pair: pair)

        let adoptions = room.state.withLock { $0.adoptions }
        #expect(adoptions.map(\.name) == ["Pancake"])
        #expect(adoptions.first?.look == CatLook(model: "mochi", coat: "ginger"))
        #expect(life.seed == 424_242)
    }

    @Test func thePartnersCareReachesThisPhonesCat() async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.fed(grams: 40))
        let life = life()
        await life.connect(room.client, pair: pair)
        #expect(life.events.map(\.kind) == [.feed])
        #expect(life.events.first?.by == "user-them")
        #expect(life.lastSeq == 1)

        var heard: [LifeEvent] = []
        life.observe { change in
            if case .event(let event) = change { heard.append(event) }
            return true
        }
        // Pushed by the room's socket.
        life.received(room.partner(.gamePlayed(game: "laser", score: 7, won: true)))
        #expect(heard.map(\.kind) == [.play])
        #expect(life.lastSeq == 2)
        // A plant watered fills no need.
        life.received(room.partner(.watered))
        #expect(heard.count == 1)
        #expect(life.lastSeq == 3)
    }

    @Test func aTouchHereGoesToTheRoomUnderItsOwnIdAndCountsOnce() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        await life.connect(room.client, pair: pair)

        life.record(.pet)
        await settle()

        let records = room.state.withLock { $0.records }
        #expect(records.map(\.event) == [.petted])
        #expect(life.events.count == 1)
        #expect(life.events.first?.id.uuidString == records.first?.id.rawValue)
        // The room's copy comes back on the socket and replaces this phone's.
        life.received(room.state.withLock { $0.entries[0] })
        #expect(life.events.count == 1)
        #expect(life.unsent.isEmpty)
    }

    @Test func aRunOfStrokesIsOnePetInThePairsJournal() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        await life.connect(room.client, pair: pair)

        life.record(.pet)
        life.record(.pet)
        life.record(.pet)
        await settle()

        #expect(room.state.withLock { $0.records }.count == 1)
        #expect(life.events.count == 3)
    }

    @Test func whatHappenedOfflineWaitsAndGoesOnTheNextSync() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        await life.connect(room.client, pair: pair)
        room.set(online: false)

        life.record([.fed(grams: 41), .gamePlayed(game: "feed", score: 90, won: true)])
        await settle()
        #expect(life.unsent.count == 2)
        #expect(life.events.map(\.kind) == [.feed, .play])

        // Kept across a launch.
        let relaunched = self.life()
        #expect(relaunched.unsent.count == 2)
        #expect(relaunched.events.count == 2)

        room.set(online: true)
        await relaunched.connect(room.client, pair: pair)
        #expect(relaunched.unsent.isEmpty)
        let stored = room.state.withLock { $0.entries }.map(\.event)
        #expect(stored == [.fed(grams: 41), .gamePlayed(game: "feed", score: 90, won: true)])
        #expect(relaunched.events.count == 2)
    }

    @Test func offlineAtLaunchSheIsTheCatAsKept() async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.petted)
        await life().connect(room.client, pair: pair)

        room.set(online: false)
        let relaunched = life()
        await relaunched.connect(room.client, pair: pair)
        #expect(relaunched.seed == 987_654_321)
        #expect(relaunched.events.map(\.by) == ["user-them"])
        #expect(relaunched.lastSeq == 1)
    }

    @Test func aNewPairStartsOverAndUnpairingLeavesThisPhonesOwnCat() async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.petted)
        let life = life()
        await life.connect(room.client, pair: pair)
        #expect(life.events.count == 1)

        await life.connect(nil, pair: nil)
        #expect(life.me == CatLife.solo)
        #expect(life.events.isEmpty)
        #expect(life.lastSeq == nil)
        // Before pairing, a touch stays on this phone.
        life.record(.pet)
        #expect(life.unsent.isEmpty)
        #expect(life.events.count == 1)

        let other = FakeCatRoom(profile: profile, caller: "user-me")
        await life.connect(other.client, pair: CatPair(me: "user-me", partner: "user-new"))
        #expect(life.events.isEmpty)
        #expect(life.context.partners == ["user-me", "user-new"])
    }

    @Test func theCatThisPhoneKeptBeforeTheRoomCarriesOver() {
        defaults.set("12345", forKey: "cat.brain.seed")
        let born = Date.now.addingTimeInterval(-86400)
        defaults.set(born, forKey: "cat.brain.born")
        let pet = LifeEvent(kind: .pet, by: "me", at: .now.addingTimeInterval(-60))
        defaults.set(try? JSONEncoder().encode([pet]), forKey: "cat.brain.events")

        let life = life()
        #expect(life.seed == 12345)
        #expect(life.context.born == born)
        #expect(life.events == [pet])
        #expect(life.me == CatLife.solo)
    }

    @Test func whatTheRoomRefusesIsLetGoAndWhatItCouldNotTakeWaits() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        await life.connect(room.client, pair: pair)

        room.state.withLock { $0.refusal = .api(.invalidRequest) }
        life.record([.petted])
        await settle()
        #expect(life.unsent.isEmpty)

        for refusal: TransportError in [.status(503), .network("lost"), .api(.unauthorized)] {
            room.state.withLock { $0.refusal = refusal }
            life.record([.fed(grams: 40)])
            await settle()
            #expect(await life.flush(), "\(refusal)")
        }
        #expect(life.unsent.count == 3)

        room.state.withLock { $0.refusal = nil }
        #expect(await life.flush() == false)
        #expect(life.unsent.isEmpty)
    }

    @Test func theOutboxKeepsOnlyTheNewestPastItsLimit() async {
        let room = FakeCatRoom(profile: profile)
        let life = life()
        await life.connect(room.client, pair: pair)
        room.set(online: false)

        life.record(Array(repeating: .petted, count: CatLife.outboxLimit))
        life.record([.fed(grams: 40)])
        await settle()
        #expect(life.unsent.count == CatLife.outboxLimit)
        #expect(life.unsent.last?.event == .fed(grams: 40))
    }

    @Test func gameEventsLeftInTheFormerOutboxGoUnderTheirOwnKeys() async throws {
        let waiting = [RecordCatEventRequest(id: .make(), event: .gamePlayed(game: "feed", score: 80, won: true))]
        try FileManager.default.createDirectory(
            at: formerOutbox.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(waiting).write(to: formerOutbox)

        let life = life()
        #expect(life.unsent == waiting)
        #expect(!FileManager.default.fileExists(atPath: formerOutbox.path))

        let room = FakeCatRoom(profile: profile)
        await life.connect(room.client, pair: pair)
        #expect(room.state.withLock { $0.records } == waiting)
        #expect(life.unsent.isEmpty)
    }
}

/// Coming back after hours away to what the partner did for her.
@MainActor
@Suite struct HomecomingTests {
    private let defaults = UserDefaults(suiteName: "HomecomingTests-\(UUID().uuidString)")!
    private let formerOutbox = URL.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)/cat-events.json")
    /// The fake room's clock, in seconds.
    private let roomNow = Date(timeIntervalSince1970: 1_800_000_000)

    private func paired(_ room: FakeCatRoom) async -> CatLife {
        let life = CatLife(defaults: defaults, formerOutbox: formerOutbox, catName: { "Pancake" },
                           catCoat: { "ginger" })
        await life.connect(room.client, pair: pair)
        return life
    }

    /// Every event the room sent so far, read up to a pet sent as a marker. Once per test: the stream has one reader.
    private func told(_ controller: RoomController) async -> [[LifeEvent.Kind]] {
        controller.petted()
        var told: [[LifeEvent.Kind]] = []
        for await event in controller.events {
            switch event {
            case .catPetted: return told
            case .partnerCared(let care): told.append(care.map(\.kind))
            case .pinOpened, .drawAsked: continue
            }
        }
        return told
    }

    private func lastSeen(hoursBefore hours: Double) {
        defaults.set(roomNow.addingTimeInterval(-hours * 3600), forKey: "cat.brain.lastSeen")
    }

    @Test func thePartnersCareIsTheirsAloneOldestFirst() async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.petted)
        room.partner(.fed(grams: 40))
        let life = await paired(room)
        life.record(.play)

        #expect(life.partnerCare(since: .distantPast).map(\.kind) == [.pet, .feed])
        #expect(life.partnerCare(since: roomNow).isEmpty)
    }

    @Test func comingBackAfterHoursTellsThePartnersCareOnce() async {
        let room = FakeCatRoom(profile: profile)
        let life = await paired(room)
        let controller = RoomController(usesStandIn: true, catLife: life, defaults: defaults)
        lastSeen(hoursBefore: 4)

        controller.cameHome(now: roomNow)
        controller.tellHomecoming(now: roomNow)
        // The journal brings the partner's meal a moment later.
        controller.catEntryArrived(room.partner(.fed(grams: 40)))
        controller.tellHomecoming(now: roomNow)
        #expect(await told(controller) == [[.feed]])
    }

    @Test(arguments: [1.0, 2.9])
    func aShortAbsenceIsNoHomecoming(hours: Double) async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.fed(grams: 40))
        let life = await paired(room)
        let controller = RoomController(usesStandIn: true, catLife: life, defaults: defaults)
        lastSeen(hoursBefore: hours)

        controller.cameHome(now: roomNow)
        controller.tellHomecoming(now: roomNow)
        #expect(await told(controller).isEmpty)
    }

    @Test func careThatArrivesLateIsNotNewsAnyMore() async {
        let room = FakeCatRoom(profile: profile)
        room.partner(.fed(grams: 40))
        let life = await paired(room)
        let controller = RoomController(usesStandIn: true, catLife: life, defaults: defaults)
        lastSeen(hoursBefore: 4)

        controller.cameHome(now: roomNow)
        controller.tellHomecoming(now: roomNow.addingTimeInterval(RoomController.homecomingWindow + 1))
        controller.tellHomecoming(now: roomNow)
        #expect(await told(controller).isEmpty)
    }
}
