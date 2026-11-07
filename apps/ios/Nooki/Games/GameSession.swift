import Combine
import FeatureGames
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

    @ObservationIgnored private let room: CatRoom
    @ObservationIgnored private let catEvents: CatEventsClient
    @ObservationIgnored private var stage: GameStage?
    @ObservationIgnored private var camera: GameCamera?
    @ObservationIgnored private var subscription: (any Cancellable)?
    @ObservationIgnored private var wasDirected = false
    @ObservationIgnored private var lens: CGSize = .zero
    @ObservationIgnored private var ended = false

    init(game: MiniGame, room: CatRoom, catEvents: CatEventsClient) {
        self.game = game
        self.room = room
        self.catEvents = catEvents
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
        subscription = room.root.scene?.subscribe(to: SceneEvents.Update.self) { [weak self] (event: SceneEvents.Update) in
            MainActor.assumeIsolated { self?.update(Float(event.deltaTime)) }
        }
        begin()
    }

    private func begin() {
        finished = nil
        deck.result = nil
        deck.bar = nil
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
        deck.tick(dt)
        stage.update(min(dt, 0.1))
        if finished == nil, let result = deck.result { finish(result) }
    }

    private func finish(_ result: GameResult) {
        finished = result
        deck.bar = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // On this phone at once, for her bars; on the server for both partners, and for the coins.
        switch result.game {
        case .feed: CatRoom.catEvents.record(.feed)
        case .brush: CatRoom.catEvents.record(.pet)
        case .laser: CatRoom.catEvents.record(.play)
        case .water: break
        }
        let events = result.events
        let client = catEvents
        Task { await client.send(events) }
    }

    func playAgain() {
        stage?.tearDown()
        begin()
    }

    /// Ends the game wherever it is: the props go, the camera eases back, and her brain takes over again.
    func close(_ done: @escaping () -> Void) {
        guard !ended else { return }
        ended = true
        stage?.tearDown()
        stage = nil
        subscription?.cancel()
        subscription = nil
        let room = room
        let directed = wasDirected
        room.walker?.directed = directed
        room.isPlayingGame = false
        if room is TabletopRoom {
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
        let touch = ray(at: point)
        switch phase {
        case .began: if let touch { stage.began(touch) }
        case .moved: if let touch { stage.moved(touch) }
        case .ended: stage.ended(touch)
        }
    }

    enum TouchPhase { case began, moved, ended }

    func act() { stage?.act() }

    private var lensNow: RoomLens? { RoomLens(camera: camera?.camera, size: lens) }

    private func ray(at point: CGPoint) -> GameTouch? {
        guard let lens = lensNow else { return nil }
        let ray = lens.ray(point)
        let origin = room.pivot.convert(position: ray.origin, from: nil)
        let direction = simd_normalize(room.pivot.convert(direction: ray.direction, from: nil))
        return GameTouch(point: point, origin: origin, direction: direction)
    }
}
