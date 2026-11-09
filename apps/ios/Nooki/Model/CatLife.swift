import Foundation
import Pet
import RoomInterface
import Transport
import Wire

/// The two accounts whose care the cat counts, once this phone is paired.
struct CatPair: Equatable {
    let me: String
    let partner: String
}

extension Couple {
    var catPair: CatPair? {
        guard let users = pair?.users, let me = users[viewer], let partner = users[other] else { return nil }
        return CatPair(me: me, partner: partner)
    }
}

/// The cat both phones share: the pair's journal from its room, this phone's touches on top, and the adopted cat's
/// seed and birth. Kept in the user defaults, so she survives offline and relaunch; offline touches wait in an
/// outbox and go once the room is reachable. Before pairing she is this phone's alone, as `LocalCatEvents` kept her.
final class CatLife: CatEventSource {
    private struct Saved: Codable {
        var events: [LifeEvent] = []
        var seed: UInt64
        var born: Date
        /// The pair's clock from the room; this phone's own until then.
        var utcOffset: Int?
        var me = CatLife.solo
        var partner: String?
        /// The last journal entry held, so a sync or a socket resumes after it.
        var lastSeq = 0
        var outbox: [RecordCatEventRequest] = []
    }

    static let key = "cat.life"
    /// This phone before it is paired.
    static let solo = "me"
    /// Events older than this no longer move her needs.
    static let kept: TimeInterval = 3 * 86400
    /// At most this many of the journal's last entries are read on a first sync: older ones are past `kept`.
    static let journalWindow = 500
    /// A run of strokes is one pet in the pair's journal and Inbox: one every 10 minutes at most.
    static let petEvery: TimeInterval = 600
    static let labsTreatGrams = 30
    /// Most events the outbox keeps; past it the oldest go, so a phone that never reaches the room doesn't grow it.
    static let outboxLimit = 200
    /// The outbox that held game events alone, before the journal came to this phone.
    nonisolated static var formerOutbox: URL {
        URL.applicationSupportDirectory.appending(path: "Outbox/cat-events.json")
    }

    private let defaults: UserDefaults
    private let catName: () -> String
    private let catCoat: () -> String
    private var saved: Saved
    private var client: CatEventsClient?
    private var observers: [(CatLifeChange) -> Bool] = []
    private var lastPetSent: Date?
    private var syncing = false
    private var flushing = false

    var events: [LifeEvent] { saved.events }
    var seed: UInt64 { saved.seed }
    var me: String { saved.me }
    var context: LifeContext {
        LifeContext(partners: [saved.me, saved.partner ?? "partner"],
                    utcOffset: saved.utcOffset ?? TimeZone.current.secondsFromGMT(), born: saved.born)
    }
    /// The journal `seq` a socket resumes after; nil while this phone holds no pair's cat. A launch reads the kept
    /// pair's, so a socket that opens before the room is reached follows her too.
    var lastSeq: Int? { isPaired ? saved.lastSeq : nil }
    private var isPaired: Bool { saved.me != Self.solo }
    /// What this phone did that the room has not stored yet.
    var unsent: [RecordCatEventRequest] { saved.outbox }

    init(defaults: UserDefaults = .standard, now: Date = .now, formerOutbox: URL = CatLife.formerOutbox,
         catName: @escaping () -> String = { CatProfile.name() },
         catCoat: @escaping () -> String = { CatCoat.current().rawValue }) {
        self.defaults = defaults
        self.catName = catName
        self.catCoat = catCoat
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = stored
        } else {
            saved = Self.fromLocalEvents(defaults, now: now)
        }
        saved.events = saved.events.filter { now.timeIntervalSince($0.at) < Self.kept }
        if let data = try? Data(contentsOf: formerOutbox),
           let waiting = try? JSONDecoder().decode([RecordCatEventRequest].self, from: data) {
            // They pay coins the phone already showed; they go under the keys they were made with.
            enqueue(waiting)
            try? FileManager.default.removeItem(at: formerOutbox)
        }
    }

    /// The cat `LocalCatEvents` kept in the defaults before the room shared her.
    private static func fromLocalEvents(_ defaults: UserDefaults, now: Date) -> Saved {
        let born = defaults.object(forKey: "cat.brain.born") as? Date ?? now
        let seed = defaults.string(forKey: "cat.brain.seed").flatMap(UInt64.init) ?? .random(in: 1...UInt64.max)
        let events = defaults.data(forKey: "cat.brain.events")
            .flatMap { try? JSONDecoder().decode([LifeEvent].self, from: $0) } ?? []
        return Saved(events: events, seed: seed, born: born)
    }

    func observe(_ handler: @escaping (CatLifeChange) -> Bool) {
        observers.append(handler)
    }

    // MARK: - This phone

    func record(_ kind: LifeEvent.Kind) {
        let id = UUID()
        append(LifeEvent(id: id, kind: kind, by: me, at: .now))
        guard let event = Self.event(for: kind) else { return }
        if kind == .pet {
            if let lastPetSent, Date.now.timeIntervalSince(lastPetSent) < Self.petEvery { return }
            lastPetSent = .now
        }
        send(RecordCatEventRequest(id: IdempotencyKey(id.uuidString), event: event))
    }

    /// What a game recorded: each event goes to the room as it is, and moves her here at once as its kind.
    func record(_ events: [CatEvent]) {
        for event in events {
            let id = UUID()
            if let kind = Self.kind(of: event) { append(LifeEvent(id: id, kind: kind, by: me, at: .now)) }
            send(RecordCatEventRequest(id: IdempotencyKey(id.uuidString), event: event))
        }
    }

    private func send(_ request: RecordCatEventRequest) {
        guard client != nil else { return }
        enqueue([request])
        Task { await flush() }
    }

    private func enqueue(_ requests: [RecordCatEventRequest]) {
        guard !requests.isEmpty else { return }
        saved.outbox.append(contentsOf: requests)
        if saved.outbox.count > Self.outboxLimit { saved.outbox.removeFirst(saved.outbox.count - Self.outboxLimit) }
        save()
    }

    // MARK: - The pair's room

    /// Follows the pair's cat through `client`, or this phone's own with nil. A different pair than the one kept
    /// starts her over from its journal; this phone's touches from before it never reached the room. What waited
    /// unpaired is this account's, from the former outbox, so it still goes.
    func connect(_ client: CatEventsClient?, pair: CatPair?) async {
        self.client = client
        let me = pair?.me ?? Self.solo
        if me != saved.me || pair?.partner != saved.partner {
            saved = Saved(seed: pair == nil ? .random(in: 1...UInt64.max) : saved.seed, born: .now, me: me,
                          partner: pair?.partner, outbox: isPaired ? [] : saved.outbox)
            save()
            notify(.reset)
        }
        await sync()
    }

    /// Reads the pair's cat and the journal entries this phone lacks, adopting her first when the room has none, and
    /// sends what waited offline. Offline, she stays as kept.
    func sync() async {
        guard let client, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do throws(TransportError) {
            var cat = try await client.load()
            if cat.cat == nil {
                cat = try await client.adopt(SaveCatRequest(
                    name: catName(), look: CatLook(model: "mochi", coat: catCoat()),
                    utcOffsetSeconds: TimeZone.current.secondsFromGMT()))
            }
            if let profile = cat.cat { take(profile) }
            _ = await flush()
            var after = max(saved.lastSeq, cat.lastSeq - Self.journalWindow)
            while true {
                let page = try await client.journal(after)
                merge(page)
                guard page.count >= CatEventsClient.journalPage, let last = page.last else { break }
                after = last.seq
            }
        } catch {}
    }

    /// An entry the room's socket pushed: the partner's, or this phone's own coming back.
    func received(_ entry: CatEntry) {
        guard isPaired else { return }
        merge([entry])
    }

    private func take(_ profile: Wire.CatProfile) {
        let seed = profile.seed ?? saved.seed
        let born = Date(timeIntervalSince1970: Double(profile.bornAt) / 1000)
        guard seed != saved.seed || born != saved.born || profile.utcOffsetSeconds != saved.utcOffset else { return }
        saved.seed = seed
        saved.born = born
        saved.utcOffset = profile.utcOffsetSeconds
        save()
        notify(.reset)
    }

    /// Sends the outbox in order, and lets go of each event the room took or refused. True while one still waits
    /// because the room couldn't take it yet; the rest stay behind it. Unpaired, nothing can go.
    func flush() async -> Bool {
        guard let client else { return false }
        guard !flushing else { return !saved.outbox.isEmpty }
        flushing = true
        defer { flushing = false }
        while let request = saved.outbox.first {
            guard !Task.isCancelled else { return true }
            do throws(TransportError) {
                let response = try await client.record(request)
                merge([response.entry])
            } catch {
                if error.isWorthRetrying { return true }
            }
            saved.outbox.removeAll { $0.id == request.id }
            save()
        }
        return false
    }

    /// Takes entries in: the room's copy of an event replaces this phone's, so both end with its time.
    private func merge(_ entries: [CatEntry]) {
        guard !entries.isEmpty else { return }
        var fresh: [LifeEvent] = []
        for entry in entries {
            saved.lastSeq = max(saved.lastSeq, entry.seq)
            guard let event = Self.lifeEvent(entry) else { continue }
            if let index = saved.events.firstIndex(where: { $0.id == event.id }) {
                saved.events[index] = event
            } else {
                saved.events.append(event)
                fresh.append(event)
            }
        }
        saved.events.removeAll { Date.now.timeIntervalSince($0.at) >= Self.kept }
        save()
        for event in fresh { notify(.event(event)) }
    }

    private func append(_ event: LifeEvent) {
        saved.events.append(event)
        save()
        notify(.event(event))
    }

    private func notify(_ change: CatLifeChange) {
        observers = observers.filter { $0(change) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.key) }
    }

    // MARK: - Between the wire and the brain

    static func lifeEvent(_ entry: CatEntry) -> LifeEvent? {
        guard let kind = kind(of: entry.event), let id = UUID(uuidString: entry.id.rawValue) else { return nil }
        return LifeEvent(id: id, kind: kind, by: entry.by.rawValue, at: Date(timeIntervalSince1970: Double(entry.at) / 1000))
    }

    /// The brain's kind for a journal event, as cat-state.md maps them. The plant fills no need.
    static func kind(of event: CatEvent) -> LifeEvent.Kind? {
        switch event {
        case .fed: .feed
        case .petted: .pet
        case .played, .gamePlayed: .play
        case .noteShared: .note
        case .slept: .sleep
        case .shooed: .shoo
        case .watered: nil
        }
    }

    /// What a touch here is in the journal. A note is the room's to record, with the note itself.
    static func event(for kind: LifeEvent.Kind) -> CatEvent? {
        switch kind {
        case .feed: .fed(grams: labsTreatGrams)
        case .pet: .petted
        case .play: .played
        case .sleep: .slept
        case .shoo: .shooed
        case .note: nil
        }
    }
}
