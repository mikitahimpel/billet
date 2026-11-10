import FeatureGames
import GamesInterface
import MomentsInterface
import OurioShared
import RealityKit
import UIKit
import UsInterface

/// Brushing: Mochi sits side-on, close up, and a finger strokes her along the back. Head to tail she purrs, leans
/// into it and loose fur flies off the brush; against the grain her ears flick and the hint says which way.
@MainActor
final class BrushStage: GameStage {
    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private let brush: Entity
    private var strokes: BrushStrokes
    private var last: CGPoint?
    private var sinceTap: Float = 0
    private var tufts: [(entity: ModelEntity, velocity: SIMD3<Float>, life: Float)] = []
    private let seat: SIMD3<Float>
    private let furTone: UInt32
    /// Radians her body turns from the player.
    private static let turn: Float = 0.85

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        strokes = BrushStrokes(length: Double(spots.length))
        furTone = BrushStage.fur(CatCoat.current())
        // A wooden brush with soft bristles, carried by the finger.
        brush = root.group()
        brush.box(0.05, 0.008, 0.02, r: 0.004, Clay.matte(0xB46C3C), at: [0, 0.012, 0])
        brush.box(0.046, 0.008, 0.018, r: 0.003, Clay.matte(0xF3E6D2, roughness: 1), at: [0, 0.005, 0])
        brush.box(0.04, 0.005, 0.008, r: 0.0025, Clay.matte(0xB46C3C), at: [0.042, 0.014, 0])
        brush.isEnabled = false
        // Three-quarters on: her face to the player, turned far enough to the left that her back shows, so a stroke
        // from her neck out to the right goes with the fur. Her neck turns the rest of the way to look at us.
        seat = spots.at(0, -0.02)
        let facing = spots.toward * cos(Self.turn) - spots.right * sin(Self.turn)
        room.send(to: seat, facing: GameSpots.yaw(from: seat, to: seat + facing), id: "brush")
        deck.say("Stroke her back, head to tail", for: 4)
        deck.bar = (0, "Groom")
    }

    var focus: [SIMD3<Float>] {
        let l = spots.length
        return [seat - spots.right * l * 0.8, seat + spots.right * l * 0.8, seat + [0, l * 0.9, 0], seat]
    }

    /// Her back, from the neck to the hips, where she is now.
    private var spine: (neck: SIMD3<Float>, hips: SIMD3<Float>)? {
        guard let walker = room.walker else { return nil }
        let l = spots.length
        let forward = SIMD3<Float>(-sin(walker.heading), 0, -cos(walker.heading))
        return (walker.at + forward * (0.12 * l) + [0, 0.62 * l, 0], walker.at - forward * (0.38 * l) + [0, 0.3 * l, 0])
    }

    var cue: GameCue? {
        guard deck.result == nil, let spine, room.walker?.moving == false else { return nil }
        return GameCue(step: 0, gesture: .drag(to: spine.hips), at: spine.neck)
    }

    func began(_ touch: GameTouch) {
        last = touch.point
    }

    func moved(_ touch: GameTouch) {
        defer { last = touch.point }
        guard let last, let spine, let neck = deck.project(spine.neck), let hips = deck.project(spine.hips) else { return }
        let move = CGPoint(x: touch.point.x - last.x, y: touch.point.y - last.y)
        let length = hypot(move.x, move.y)
        // Only on her: near the line of her back on screen.
        let (along, gap) = Self.closest(touch.point, neck, hips)
        let perMeter = deck.pointsPerMeter(spine.neck)
        guard gap < CGFloat(0.4 * spots.length) * perMeter, length > 0.5 else {
            brush.isEnabled = false
            return
        }
        let grain = CGPoint(x: hips.x - neck.x, y: hips.y - neck.y)
        let grainLength = max(hypot(grain.x, grain.y), 1)
        let fit = Double((move.x * grain.x + move.y * grain.y) / (length * grainLength))
        let point = simd_mix(spine.neck, spine.hips, SIMD3(repeating: Float(along))) + spots.toward * (0.08 * spots.length)
        brush.isEnabled = true
        brush.position = point
        brush.orientation = simd_quatf(from: [1, 0, 0], to: simd_normalize(spine.hips - spine.neck))
        let tuftsBefore = strokes.tufts
        switch strokes.stroke(distance: Double(length / perMeter), fit: fit) {
        case .enjoys(let purrs):
            if purrs {
                room.walker?.pet()
                deck.cheer()
            }
            if sinceTap > 0.12 {
                sinceTap = 0
                deck.stroke()
            }
        case .flinches:
            room.walker?.behavior.perform(.flick)
            deck.say(BrushStrokes.wrongWay, for: 1.8)
        case nil: break
        }
        for _ in tuftsBefore..<strokes.tufts { shed(at: point) }
    }

    func ended(_ touch: GameTouch?) {
        last = nil
        brush.isEnabled = false
    }

    func update(_ dt: Float) {
        sinceTap += dt
        strokes.update(dt: Double(dt))
        deck.show(strokes.groom, "Groom")
        for index in tufts.indices.reversed() {
            tufts[index].life -= dt
            tufts[index].velocity.y -= 0.02 * dt
            tufts[index].entity.position += tufts[index].velocity * dt
            tufts[index].entity.scale *= 1 + dt * 0.3
            if tufts[index].life <= 0 {
                tufts[index].entity.removeFromParent()
                tufts.remove(at: index)
            }
        }
        if strokes.isDone, deck.result == nil {
            brush.isEnabled = false
            deck.cheer(big: true)
            deck.result = GameResult(game: .brush, score: 100)
        }
    }

    private func shed(at point: SIMD3<Float>) {
        guard tufts.count < 24 else { return }
        let tuft = root.sphere(0.004, Clay.matte(furTone, roughness: 1), at: point, scale: [1.4, 0.8, 1.1])
        let drift = spots.toward * Float.random(in: 0.01...0.03) + spots.right * Float.random(in: -0.02...0.02)
        tufts.append((tuft, drift + [0, Float.random(in: 0.02...0.05), 0], 2.2))
    }

    /// How far along the segment `a`-`b` the point nearest `p` lies (0...1), and how far `p` is from it.
    private static func closest(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> (CGFloat, CGFloat) {
        let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
        let lengthSquared = max(ab.x * ab.x + ab.y * ab.y, 1)
        let t = min(max(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / lengthSquared, 0), 1)
        let near = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
        return (t, hypot(p.x - near.x, p.y - near.y))
    }

    private static func fur(_ coat: CatCoat) -> UInt32 {
        switch coat {
        case .grey: 0xB8B2AB
        case .ginger: 0xE39A55
        case .cream: 0xF1DDBF
        case .tuxedo, .black: 0x3A3532
        case .calico: 0xF6E3C8
        }
    }

    func tearDown() {
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
