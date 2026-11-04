import Foundation
import Observation
import Pet
import simd

/// What the couple did for the cat, and who they are: the brain's input. The stub keeps this
/// phone's own touches; the server's feed of both partners' notes, meals and pets takes its place.
protocol CatEventSource: AnyObject {
    var events: [LifeEvent] { get }
    var context: LifeContext { get }
    /// The cat's seed: the same on both phones, so both see the same cat.
    var seed: UInt64 { get }
    /// This phone's device in `context.partners`.
    var me: String { get }
    /// Calls `handler` with each new event, so a brain takes it at once, until it returns false.
    func observe(_ handler: @escaping (LifeEvent) -> Bool)
    func record(_ kind: LifeEvent.Kind)
}

/// Where the brain's changes go, for the app's analytics.
protocol CatAnalytics: AnyObject {
    func catChanged(from: CatMind?, to: CatMind, cause: String)
    /// Something one of the couple did that the cat answered.
    func coupleEvent(_ name: String)
}

final class NoCatAnalytics: CatAnalytics {
    func catChanged(from: CatMind?, to: CatMind, cause: String) {}
    func coupleEvent(_ name: String) {}
}

/// The cat's life as only this phone knows it, kept for three days in the user defaults.
final class LocalCatEvents: CatEventSource {
    private static let eventsKey = "cat.brain.events"
    private static let bornKey = "cat.brain.born"
    private static let seedKey = "cat.brain.seed"
    private static let kept: TimeInterval = 3 * 86400

    private let defaults: UserDefaults
    private(set) var events: [LifeEvent]
    let context: LifeContext
    let seed: UInt64
    let me = "me"
    private var observers: [(LifeEvent) -> Bool] = []

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        let born = defaults.object(forKey: Self.bornKey) as? Date ?? now
        defaults.set(born, forKey: Self.bornKey)
        if let stored = defaults.string(forKey: Self.seedKey), let seed = UInt64(stored) {
            self.seed = seed
        } else {
            seed = .random(in: 1...UInt64.max)
            defaults.set(String(seed), forKey: Self.seedKey)
        }
        context = LifeContext(partners: ["me", "partner"], utcOffset: TimeZone.current.secondsFromGMT(), born: born)
        let data = defaults.data(forKey: Self.eventsKey)
        let stored = data.flatMap { try? JSONDecoder().decode([LifeEvent].self, from: $0) } ?? []
        events = stored.filter { now.timeIntervalSince($0.at) < Self.kept }
    }

    func record(_ kind: LifeEvent.Kind) {
        let event = LifeEvent(kind: kind, by: me, at: .now)
        events.append(event)
        if let data = try? JSONEncoder().encode(events) { defaults.set(data, forKey: Self.eventsKey) }
        observers = observers.filter { $0(event) }
    }

    func observe(_ handler: @escaping (LifeEvent) -> Bool) {
        observers.append(handler)
    }
}

/// Mochi's brain in a room: steps a ``CatBrainRunner`` on the wall clock, reads it as the owner's
/// ``CatMind`` and plays it through ``NookiCatScript`` with Ilya's walker and habits. It publishes
/// what the Labs card shows only when it changes.
@Observable
final class CatDirector {
    private(set) var mind: CatMind?
    private(set) var path = ""
    private(set) var needs: PetNeeds?
    private(set) var lastEvent = "–"
    private(set) var top: [CatUtilityScore] = []
    private(set) var rest = NookiRestPose.sit
    private(set) var spot = NookiSpot.home

    /// Hours away after which opening the app is a homecoming she greets.
    static let greetAfter: TimeInterval = 3 * 3600
    private static let lastSeenKey = "cat.brain.lastSeen"

    @ObservationIgnored private let walker: CatWalker
    @ObservationIgnored private let spots: [NookiSpot: CatWalker.Destination]
    @ObservationIgnored private let source: CatEventSource
    @ObservationIgnored private let analytics: CatAnalytics
    @ObservationIgnored private let defaults: UserDefaults
    /// Which way the camera is from the room's middle, along the floor, for where "at you" is.
    @ObservationIgnored private let cameraDirection: () -> SIMD3<Float>
    @ObservationIgnored private var runner: CatBrainRunner
    @ObservationIgnored private var script: NookiCatScript
    @ObservationIgnored private var look = NookiLook.around
    @ObservationIgnored private var liveUntil = 0.0
    @ObservationIgnored private var holdUntil = 0.0
    @ObservationIgnored private var nextThink = 0.0
    @ObservationIgnored private var nextSeen = 0.0
    @ObservationIgnored var paused = false
    /// Whether the brain drives her; read a few times a second, so the Labs switch takes effect at once.
    @ObservationIgnored private let enabled: () -> Bool

    init(walker: CatWalker, spots: [NookiSpot: CatWalker.Destination], source: CatEventSource,
         analytics: CatAnalytics, defaults: UserDefaults = .standard,
         enabled: @escaping () -> Bool = { AppSettings.catBrain }, cameraDirection: @escaping () -> SIMD3<Float>) {
        self.walker = walker
        self.spots = spots
        self.source = source
        self.analytics = analytics
        self.defaults = defaults
        self.cameraDirection = cameraDirection
        self.enabled = enabled
        let available = Set(spots.keys).union([.home])
        script = NookiCatScript(spots: available)
        runner = CatBrainRunner(events: source.events, now: Date.now.timeIntervalSince1970, context: source.context,
                                seed: source.seed, room: NookiSpot.affordances(available))
        source.observe { [weak self] event in
            guard let self else { return false }
            receive(event)
            return true
        }
    }

    // MARK: - The couple

    /// A stroke on this phone: she leans in now and the brain hears of it.
    func petted() {
        live(.petted(.head), for: 2.5)
        source.record(.pet)
        analytics.coupleEvent("pet")
    }

    /// The app came to the front; after a few hours away she comes to greet you.
    func appOpened(now: Date = .now) {
        let last = defaults.object(forKey: Self.lastSeenKey) as? Date
        defaults.set(now, forKey: Self.lastSeenKey)
        guard let last, now.timeIntervalSince(last) >= Self.greetAfter else { return }
        live(.greeting, for: 4)
        lastEvent = "greeting after \(Int(now.timeIntervalSince(last) / 3600)) h"
        analytics.coupleEvent("greeting")
    }

    /// Someone sent her to `spot` with a tap: she stays there a minute before the brain moves her on, and a toy is a
    /// game.
    func sent(to spot: NookiSpot) {
        holdUntil = Date.now.timeIntervalSince1970 + 60
        lastEvent = "sent to \(spot.rawValue)"
        if spot == .ball || spot == .basket { source.record(.play) }
    }

    private func receive(_ event: LifeEvent) {
        let now = Date.now.timeIntervalSince1970
        runner.receive([event], now: now)
        lastEvent = "\(event.kind.rawValue) by \(event.by)"
        nextThink = 0
    }

    private func live(_ interaction: CatInteraction, for seconds: Double) {
        runner.live = interaction
        liveUntil = Date.now.timeIntervalSince1970 + seconds
        nextThink = 0
    }

    // MARK: - Each frame

    func update(_ dt: Float) {
        guard !paused else { return }
        let now = Date.now.timeIntervalSince1970
        if now >= nextSeen {
            defaults.set(Date(timeIntervalSince1970: now), forKey: Self.lastSeenKey)
            nextSeen = now + 60
        }
        if runner.live != nil, now >= liveUntil { runner.live = nil }
        if now >= nextThink {
            nextThink = now + 0.25
            guard drive(enabled()) else { return }
            think(now)
        }
        if walker.directed { walker.behavior.focus = focus() }
    }

    /// Hands her to the brain or back to Ilya's own timers, sitting and wide awake. Returns whether the brain drives.
    private func drive(_ on: Bool) -> Bool {
        guard on != walker.directed else { return on }
        if !on {
            walker.settle(.sit)
            guard walker.rest == .sit else { return true }
            walker.behavior.focus = nil
            walker.behavior.sleepiness = 0
        } else {
            script = NookiCatScript(spots: script.spots)
        }
        walker.directed = on
        return on
    }

    private func think(_ now: Double) {
        runner.advance(to: now)
        let frame = runner.frame
        let mind = CatMind(frame.stack, hour: runner.brain.hour(at: now))
        if mind != self.mind {
            let cause = runner.brain.transitions.last?.cause.rawValue ?? (frame.stack.interaction == nil ? "start" : "touch")
            analytics.catChanged(from: self.mind, to: mind, cause: cause)
            self.mind = mind
        }
        let body = NookiCatBody(moving: walker.moving, at: here, rest: walker.rest)
        for intent in script.next(frame, mind: mind, body: body, now: now) { apply(intent, now: now) }
        publish(frame, now: now)
    }

    private var here: NookiSpot {
        guard let id = walker.place else { return .home }
        return spots.first { $0.value.id == id }?.key ?? .home
    }

    private func apply(_ intent: NookiCatIntent, now: Double) {
        switch intent {
        case .go(let spot, let stretch):
            guard now >= holdUntil else { return }
            walker.go(to: spot == .home ? nil : spots[spot], stretch: stretch)
        case .rest(let pose):
            walker.settle(pose)
        case .act(let act):
            switch act {
            case .yawn: walker.behavior.perform(.yawn)
            case .slowBlink: walker.behavior.perform(.slowBlink)
            case .listen: walker.behavior.perform(.listen)
            case .twitch: walker.behavior.perform(.twitch)
            case .flick: walker.behavior.perform(.flick)
            case .curl: walker.behavior.perform(.curl)
            case .groom: walker.behavior.perform(.groom)
            case .pats: walker.pats()
            }
        case .look(let look):
            self.look = look
        case .drowse(let amount):
            walker.behavior.sleepiness = Float(amount)
        }
    }

    /// Her head's heading for `look`, relative to her body and within what her neck turns.
    private func focus() -> Float? {
        let target: SIMD3<Float>
        switch look {
        case .around: return nil
        case .camera, .away:
            target = walker.at + cameraDirection() * (look == .away ? -1 : 1)
        case .window:
            guard let sill = spots[.sill]?.path.last?.at else { return nil }
            target = sill
        case .spot(let spot):
            guard let at = spots[spot]?.path.last?.at else { return nil }
            target = at
        }
        let d = target - walker.at
        let heading = atan2(-d.x, -d.z)
        let turn = atan2(sin(heading - walker.heading), cos(heading - walker.heading))
        return min(max(turn, -0.6), 0.6)
    }

    private func publish(_ frame: CatBrainFrame, now: Double) {
        let path = frame.stack.path
        if path != self.path { self.path = path }
        let needs = runner.brain.utilityInput(at: now).needs
        if needs != self.needs { self.needs = needs }
        let top = Array(runner.brain.scores.sorted { $0.score > $1.score }.prefix(3))
        if top != self.top { self.top = top }
        if walker.rest != rest { rest = walker.rest }
        if here != spot { spot = here }
    }
}
