import DecorInterface
import FeatureGames
import GamesInterface
import RealityKit
import UIKit

/// The laser dot: drag it across the floor and Mochi runs after it; let it rest close to her and she pounces.
/// Chasing and pouncing fill the play bar; full, she sits down pleased.
@MainActor
final class LaserStage: GameStage {
    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private var laser: LaserPlay
    private let dot: Entity
    private let halo: ModelEntity
    private var aim: SIMD3<Float>?
    /// Where she was last frame while running after it, to count how far she ran.
    private var running: SIMD3<Float>?
    private var chases = 0
    private var pouncing = false
    private var time: Float = 0
    /// Where the dot has been, newest first, drawn as a fading trail so the path reads.
    private var trail: [SIMD3<Float>] = []
    private let trailDots: [ModelEntity]
    /// A trail dot's own size: the meshes are unit cylinders, so a scale that drops it leaves a metre-wide disc.
    private static let trailSize = SIMD3<Float>(0.006, 0.001, 0.006)
    private var sinceTrail: Float = 0
    private let lesson: (start: SIMD2<Double>, end: SIMD2<Double>)
    /// Seconds since a finger was last down; the dot waits at the lesson's start once it has been a while.
    private var untouched: Float = 99

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        let root = room.pivot.group()
        self.root = root
        laser = LaserPlay(length: Double(spots.length), floor: spots.area)
        lesson = LaserPlay.lesson(on: spots.area)
        dot = root.group()
        let core = dot.cylinder(0.002, 0.011, Clay.glow(0xFF2A1F, intensity: 3), at: .zero)
        var glow = UnlitMaterial(color: UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 0.4))
        glow.blending = .transparent(opacity: .init(floatLiteral: 0.4))
        halo = dot.cylinder(0.001, 0.02, glow, at: [0, 0.0005, 0])
        dot.isEnabled = false
        trailDots = (0..<14).map { _ in
            root.cylinder(0.001, 0.006, Clay.glow(0xFF6A55, intensity: 3), at: .zero)
        }
        // Drawn after the opaque room, still tested against its depth: a nap of fabric cannot swallow the dot, and
        // a wall or a chair in front of it still hides it.
        let late = ModelSortGroupComponent(group: ModelSortGroup(depthPass: .postPass), order: 1)
        for entity in [core, halo] + trailDots { entity.components.set(late) }
        trailDots.forEach { $0.isEnabled = false }
        deck.say(LaserPlay.goal)
        deck.show(0, "Played")
        let seat = spots.at(0, -0.05)
        room.send(to: seat, facing: GameSpots.yaw(from: seat, to: seat + spots.toward), id: "laser-start")
    }

    var focus: [SIMD3<Float>] {
        var points = [spots.at(-0.2, -0.14), spots.at(0.2, -0.14), spots.at(-0.2, 0.2), spots.at(0.2, 0.2), spots.at(0, 0, up: 0.12)]
        points += [lessonPoint(lesson.start), lessonPoint(lesson.end)]
        if room is TabletopRoom { points.append(spots.at(0, -0.6, up: 0.4)) }
        return points
    }

    var cue: GameCue? {
        guard deck.result == nil, chases == 0 || !(room.walker?.moving ?? false) else { return nil }
        return GameCue(step: 0, gesture: .drag(to: lessonPoint(lesson.end)), at: lessonPoint(lesson.start))
    }

    private func lessonPoint(_ p: SIMD2<Double>) -> SIMD3<Float> { [Float(p.x), surface(p.x, p.y), Float(p.y)] }

    /// The height of what lies under a floor point: the floor, or the top of a rug there.
    private func surface(_ x: Double, _ z: Double) -> Float {
        Float(FlatSurface.height(atX: x, z: z, floor: Double(spots.floor), over: room.flatSurfaces()))
    }

    func began(_ touch: GameTouch) {
        moved(touch)
    }

    func moved(_ touch: GameTouch) {
        if let point = touch.onPlane(y: spots.floor) { aim = point }
    }

    func ended(_ touch: GameTouch?) { aim = nil }

    func update(_ dt: Float) {
        time += dt
        laser.aim(aim.map { SIMD2(Double($0.x), Double($0.z)) }, dt: Double(dt))
        untouched = aim == nil ? untouched + dt : 0
        // With no finger down the dot waits where the hand takes it, so there is always something to drag.
        let shown = laser.dot ?? (untouched > 1.2 && deck.result == nil ? lesson.start : nil)
        if let at = shown {
            dot.isEnabled = true
            dot.position = [Float(at.x), surface(at.x, at.y) + 0.002, Float(at.y)]
            let pulse = sin(time * 30)
            halo.scale = SIMD3(repeating: 1 + 0.25 * pulse * pulse) * [0.027, 0.001, 0.027]
            sinceTrail += dt
            if laser.dot != nil, sinceTrail > 0.035 {
                sinceTrail = 0
                trail.insert(dot.position, at: 0)
                if trail.count > trailDots.count { trail.removeLast() }
            }
        } else {
            dot.isEnabled = false
            if !trail.isEmpty { trail.removeLast() }
        }
        for (index, entity) in trailDots.enumerated() {
            entity.isEnabled = index < trail.count
            guard index < trail.count else { continue }
            entity.position = trail[index]
            entity.scale = SIMD3(repeating: 1 - Float(index) / Float(trailDots.count + 2)) * Self.trailSize
        }
        guard let walker = room.walker else { return }
        let at = walker.at
        if walker.moving {
            if let running { laser.ran(Double(simd_distance(SIMD2(at.x, at.z), SIMD2(running.x, running.z)))) }
            if chases > 0 { running = at }
        } else {
            running = nil
            if pouncing {
                pouncing = false
                laser.pounced()
                deck.thump()
                deck.cheer()
                deck.say(laser.cheer, for: 0.9)
            }
            if deck.result == nil, laser.isDone {
                dot.isEnabled = false
                deck.cheer(big: true)
                deck.result = GameResult(game: .laser, score: 100)
            } else if let cue = laser.cue(cat: SIMD2(Double(at.x), Double(at.z))) {
                switch cue {
                case .chase(let p): run(to: p, from: at, pounce: false)
                case .pounce(let p): run(to: p, from: at, pounce: true)
                }
            }
        }
        deck.show(laser.play, "Played")
    }

    /// Runs her to the dot, stopping short of it so her fore paws land on it; a pounce ends in paw pats.
    private func run(to p: SIMD2<Double>, from at: SIMD3<Float>, pounce: Bool) {
        let target = SIMD3(Float(p.x), surface(p.x, p.y), Float(p.y))
        let gap = simd_distance(target, at)
        let short = min(0.3 * spots.length, gap * 0.9)
        let stop = gap > 0.001 ? target + (at - target) / gap * short : target
        chases += 1
        pouncing = pounce
        room.send(to: [stop.x, surface(Double(stop.x), Double(stop.z)), stop.z], facing: GameSpots.yaw(from: at, to: target),
                  id: "laser-\(chases)", play: pounce)
    }

    func tearDown() {
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
