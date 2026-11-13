import Combine
import FeatureGames
import GamesInterface
import Pet
import RealityKit
import SwiftUI

/// One mini-game in the room, from the first frame to the cat going home: it builds the stage, holds the room's
/// brain back, frames the camera, runs the stage each frame and, once it is done, writes the care into the
/// couple's journal.
@MainActor
@Observable
final class GameSession {
    let game: MiniGame
    let deck = GameDeck()
    /// The finished game's toast, while it shows.
    private(set) var finished: GameResult?
    /// Where the hand shows the gesture to make, while it shows.
    private(set) var pointer: GamePointer?

    /// The goal line while it is the one she was shown at the start; after the first touch only a new line shows.
    var shownHint: String? { deck.hint == goalSeen ? nil : deck.hint }
    private var goalSeen: String?

    @ObservationIgnored private let room: CatRoom
    @ObservationIgnored private let catLife: CatLife
    @ObservationIgnored private var stage: GameStage?
    @ObservationIgnored private var camera: GameCamera?
    @ObservationIgnored private var subscription: (any Cancellable)?
    @ObservationIgnored private var wasDirected = false
    @ObservationIgnored private var lens: CGSize = .zero
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var coach = GameCoach.State.idle
    @ObservationIgnored private var gaze = GameGaze()
    @ObservationIgnored private var finger: CGPoint?
    @ObservationIgnored private var sinceTwitch: Float = 9
    @ObservationIgnored private var unseen: Float = 0
    @ObservationIgnored private var sparkles: GameSparkles?
    @ObservationIgnored private let spots: GameSpots

    init(game: MiniGame, room: CatRoom, catLife: CatLife) {
        self.game = game
        self.room = room
        self.catLife = catLife
        spots = GameSpots(room: room)
    }

    var action: String? { finished == nil ? stage?.action : nil }

    func start(viewport: CGSize) {
        guard stage == nil, !ended else { return }
        lens = viewport
        // The corner is in its view and Mochi in it a moment after the view appears.
        if let corner = room as? TabletopRoom, !corner.isReady {
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                start(viewport: lens)
            }
            return
        }
        room.isPlayingGame = true
        wasDirected = room.walker?.directed ?? false
        room.walker?.directed = true
        let camera = GameCamera(room: room)
        camera.viewport = viewport
        self.camera = camera
        let pivot = room.pivot
        deck.project = { [weak self] point in self?.lensNow?.project(pivot.convert(position: point, to: nil)) }
        deck.pointsPerMeter = { [weak self] point in
            self?.lensNow?.pointsPerMeter(at: pivot.convert(position: point, to: nil)) ?? 1
        }
        sparkles = GameSparkles(in: room.pivot)
        subscription = room.root.scene?.subscribe(to: SceneEvents.Update.self) { [weak self] (event: SceneEvents.Update) in
            MainActor.assumeIsolated { self?.update(Float(event.deltaTime)) }
        }
        begin()
    }

    private func begin() {
        finished = nil
        deck.result = nil
        deck.bar = nil
        goalSeen = nil
        coach = .idle
        pointer = nil
        let stage = Self.stage(for: game, room: room, deck: deck)
        self.stage = stage
        camera?.focus = stage.focus
    }

    private static func stage(for game: MiniGame, room: CatRoom, deck: GameDeck) -> GameStage {
        switch game {
        case .feed: FeedStage(room: room, deck: deck)
        case .water: WaterStage(room: room, deck: deck)
        case .laser: LaserStage(room: room, deck: deck)
        case .brush: BrushStage(room: room, deck: deck)
        }
    }

    func resize(_ viewport: CGSize) {
        lens = viewport
        camera?.viewport = viewport
    }

    private func update(_ dt: Float) {
        guard dt > 0, let stage else { return }
        sinceTwitch += dt
        deck.tick(dt)
        stage.update(min(dt, 0.1))
        camera?.push = stage.push
        for big in deck.takeCheers() { cheer(big: big) }
        look(dt)
        keepInView(dt)
        coach = GameCoach.transition(coach, .tick(Double(dt))).0
        let cue = finished == nil ? stage.cue : nil
        coach = GameCoach.transition(coach, .step(cue?.step)).0
        show(coach.shown == nil ? nil : cue)
        if finished == nil, let result = deck.result { finish(result) }
    }

    // MARK: - Her

    /// She stays in the frame: should her head be off screen while she sits still, she is shown again and sent back
    /// to her seat. A position no room can show, or a cat nothing of whom is drawn, is the room's own `CatWatch`'s.
    private func keepInView(_ dt: Float) {
        guard let walker = room.walker, let seat = stage?.seat, !walker.moving, CatWatch.isInRoom(walker.at), let head else {
            return
        }
        if OnScreen.contains(deck.project(head), in: lens) {
            unseen = 0
            return
        }
        unseen += dt
        guard unseen > 0.8 else { return }
        unseen = 0
        walker.show()
        room.send(to: seat, facing: spots.facingPlayer, id: "keep-watch")
    }

    /// Just above her eyes, in the pivot's space.
    private var head: SIMD3<Float>? {
        room.walker.map { $0.at + [0, spots.length * 0.8, 0] }
    }

    /// Her eyes on the finger while it is down, otherwise mostly on the player.
    private func look(_ dt: Float) {
        switch gaze.update(dt: Double(dt), touching: finger != nil) {
        case .finger:
            guard let finger, let head, let at = deck.project(head) else { return }
            room.follow(CGSize(width: finger.x - at.x, height: finger.y - at.y))
        case .player: room.follow(stage?.glance ?? .zero)
        case .free: room.follow(nil)
        }
    }

    /// A happy squint at the player, a purr and a puff of sparks.
    private func cheer(big: Bool) {
        guard let walker = room.walker else { return }
        walker.behavior.perform(.slowBlink)
        walker.pet()
        gaze.pleased()
        if let head { sparkles?.burst(at: head + [0, spots.length * 0.25, 0], big: big) }
    }

    /// Moves the hand only when its place on screen has moved by a few points: each write re-renders it.
    private func show(_ cue: GameCue?) {
        guard let cue, let from = deck.project(cue.at) else {
            if pointer != nil { pointer = nil }
            return
        }
        let next: GamePointer
        switch cue.gesture {
        case .tap: next = GamePointer(gesture: .tap, from: from, to: nil)
        case .hold: next = GamePointer(gesture: .hold, from: from, to: nil)
        case .rub: next = GamePointer(gesture: .rub, from: from, to: nil)
        case .drag(let end): next = GamePointer(gesture: .drag, from: from, to: deck.project(end))
        }
        if let pointer, pointer.isNear(next) { return }
        pointer = next
    }

    private func finish(_ result: GameResult) {
        finished = result
        camera?.covered = 0.36
        finger = nil
        deck.bar = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // On this phone at once, for her bars; in the pair's journal for both partners, and for the coins.
        catLife.record(result.events)
        if result.game == .feed, result.tooMuch { catLife.record(.overfeed) }
    }

    func playAgain() {
        stage?.tearDown()
        camera?.covered = 0
        begin()
    }

    /// Ends the game wherever it is: the props go, the camera eases back, and her brain takes over again. `now` lets
    /// the camera go at once, for a game that moves to another scene and covers this one.
    func close(now: Bool = false, _ done: @escaping () -> Void) {
        guard !ended else { return }
        ended = true
        stage?.tearDown()
        stage = nil
        subscription?.cancel()
        subscription = nil
        pointer = nil
        sparkles?.remove()
        sparkles = nil
        room.follow(nil)
        let room = room
        let directed = wasDirected
        room.walker?.directed = directed
        room.isPlayingGame = false
        if room is TabletopRoom || now {
            camera?.cancel()
            done()
        } else if let camera {
            camera.release(done)
        } else {
            done()
        }
    }

    // MARK: - Touches

    func touch(_ phase: TouchPhase, at point: CGPoint) {
        guard finished == nil, let stage else { return }
        finger = phase == .ended ? nil : point
        let touch = ray(at: point)
        switch phase {
        case .began:
            if goalSeen == nil { goalSeen = deck.hint ?? "" }
            coach = GameCoach.transition(coach, .touched).0
            react()
            if let touch { stage.began(touch) }
        case .moved: if let touch { stage.moved(touch) }
        case .ended: stage.ended(touch)
        }
    }

    enum TouchPhase { case began, moved, ended }

    /// Every touch gets an ear: a flick of one now and then, so it never turns into a tic.
    private func react() {
        guard sinceTwitch > 1.2, let walker = room.walker, !walker.moving else { return }
        sinceTwitch = 0
        walker.behavior.perform(.twitch)
    }

    func act() { stage?.act() }

    var assist: String? { finished == nil ? stage?.assist : nil }

    func assistAct() { stage?.assistAct() }

    private var lensNow: RoomLens? { RoomLens(camera: camera?.camera, size: lens) }

    private func ray(at point: CGPoint) -> GameTouch? {
        guard let lens = lensNow else { return nil }
        let ray = lens.ray(point)
        let origin = room.pivot.convert(position: ray.origin, from: nil)
        let direction = simd_normalize(room.pivot.convert(direction: ray.direction, from: nil))
        return GameTouch(point: point, origin: origin, direction: direction)
    }
}

/// The hint hand on screen: the gesture, where it starts and, for a drag, where it ends.
struct GamePointer: Equatable {
    enum Gesture { case tap, hold, rub, drag }

    let gesture: Gesture
    let from: CGPoint
    let to: CGPoint?

    func isNear(_ other: GamePointer) -> Bool {
        guard gesture == other.gesture, (to == nil) == (other.to == nil) else { return false }
        let close = { (a: CGPoint, b: CGPoint) in hypot(a.x - b.x, a.y - b.y) < 4 }
        return close(from, other.from) && (to.flatMap { a in other.to.map { close(a, $0) } } ?? true)
    }
}
