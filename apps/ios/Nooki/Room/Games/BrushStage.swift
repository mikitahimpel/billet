import FeatureGames
import GamesInterface
import MomentsInterface
import WidgetInterface
import WidgetUI
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
    /// Hearts and sparks that rise from the bristles and shrink away: (entity, velocity, life, shrink per second).
    private var pops: [(entity: Entity, velocity: SIMD3<Float>, life: Float, shrink: Float)] = []
    private let guide: Entity
    private let guideDots: [ModelEntity]
    private let arrow: [ModelEntity]
    private var touching = false
    private var sinceTouch: Float = 99
    private var time: Float = 0
    private var hearted = 0
    private let seat: SIMD3<Float>
    private let furTone: UInt32
    /// Radians her body turns from the player.
    private static let turn: Float = 0.55
    private static let brushScale: Float = 2.2

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        strokes = BrushStrokes(length: Double(spots.length))
        furTone = BrushStage.fur(CatCoat.current())
        // A big wooden brush with soft bristles, carried by the finger and held in front of her, so her body never
        // covers it.
        brush = root.group()
        let head = brush.group()
        head.box(0.05, 0.008, 0.02, r: 0.004, Clay.matte(0xB46C3C), at: [0, 0.012, 0])
        head.box(0.046, 0.009, 0.018, r: 0.003, Clay.matte(0xF8E8CC, roughness: 1), at: [0, 0.0045, 0])
        for x in stride(from: Float(-0.018), through: 0.018, by: 0.009) {
            head.box(0.004, 0.004, 0.016, r: 0.0015, Clay.matte(0xFFF3E0, roughness: 1), at: [x, 0.0005, 0])
        }
        head.box(0.04, 0.007, 0.009, r: 0.003, Clay.matte(0xB46C3C), at: [0.042, 0.016, 0])
        head.scale = SIMD3(repeating: Self.brushScale)
        brush.isEnabled = false
        let guideNode = root.group()
        guide = guideNode
        guideDots = (0..<5).map { _ in guideNode.sphere(0.006, Clay.glow(0xFFC25A, intensity: 2.5), at: .zero) }
        arrow = [Float(0.7), -0.7].map { guideNode.box(0.03, 0.005, 0.005, r: 0.002, Clay.glow(0xFFC25A, intensity: 2.5), at: .zero, rotation: .z($0)) }
        // Three-quarters on: her face to the player, turned far enough to the left that her back shows, so a stroke
        // from her neck out to the right goes with the fur. Her neck turns the rest of the way to look at us.
        seat = spots.at(0, -0.02)
        let facing = spots.toward * cos(Self.turn) - spots.right * sin(Self.turn)
        room.send(to: seat, facing: GameSpots.yaw(from: seat, to: seat + facing), id: "brush")
        deck.say(BrushStrokes.goal)
        deck.show(0, "Groomed")
    }

    var focus: [SIMD3<Float>] {
        let l = spots.length
        return [seat - spots.right * l * 0.6, seat + spots.right * l * 0.6, seat + [0, l * 0.9, 0], seat]
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
        touching = true
        carry(touch)
    }

    /// Holds the brush where the finger is, on a plane in front of her back so it is always drawn over her.
    private func carry(_ touch: GameTouch) {
        guard let spine else { return }
        let plane = spine.neck + spots.toward * (0.32 * spots.length)
        let facing = simd_dot(touch.direction, spots.toward)
        guard abs(facing) > 1e-4 else { return }
        let t = simd_dot(plane - touch.origin, spots.toward) / facing
        guard t > 0 else { return }
        brush.isEnabled = true
        brush.position = touch.origin + touch.direction * t
        brush.orientation = brushPose
    }

    /// Long side across the screen, bristles down and tipped toward her back.
    private var brushPose: simd_quatf {
        simd_quatf(from: [1, 0, 0], to: spots.right) * simd_quatf(angle: 0.9, axis: [1, 0, 0])
    }

    func moved(_ touch: GameTouch) {
        defer { last = touch.point }
        carry(touch)
        sinceTouch = 0
        guard let last, let spine, let neck = deck.project(spine.neck), let hips = deck.project(spine.hips) else { return }
        let move = CGPoint(x: touch.point.x - last.x, y: touch.point.y - last.y)
        let length = hypot(move.x, move.y)
        // Only on her: near the line of her back on screen.
        let (along, gap) = Self.closest(touch.point, neck, hips)
        let perMeter = deck.pointsPerMeter(spine.neck)
        guard gap < CGFloat(0.4 * spots.length) * perMeter, length > 0.5 else { return }
        let grain = CGPoint(x: hips.x - neck.x, y: hips.y - neck.y)
        let grainLength = max(hypot(grain.x, grain.y), 1)
        let fit = Double((move.x * grain.x + move.y * grain.y) / (length * grainLength))
        let point = simd_mix(spine.neck, spine.hips, SIMD3(repeating: Float(along))) + spots.toward * (0.08 * spots.length)
        let tuftsBefore = strokes.tufts
        switch strokes.stroke(distance: Double(length / perMeter), fit: fit) {
        case .enjoys(let purrs):
            if purrs {
                room.walker?.pet()
                deck.cheer()
                heart(at: brush.position + [0, 0.02, 0])
            }
            if sinceTap > 0.12 {
                sinceTap = 0
                deck.stroke()
                spark(at: brush.position)
            }
        case .flinches:
            room.walker?.behavior.perform(.flick)
            deck.say(BrushStrokes.wrongWay, for: 1.8)
        case nil: break
        }
        for _ in tuftsBefore..<strokes.tufts {
            shed(at: point)
            hearted += 1
            if hearted % 8 == 0 {
                deck.tap(0.8)
                heart(at: brush.position + [Float.random(in: -0.02...0.02), 0.03, 0])
            }
        }
    }

    func ended(_ touch: GameTouch?) {
        last = nil
        touching = false
    }

    func update(_ dt: Float) {
        sinceTap += dt
        time += dt
        if !touching { sinceTouch += dt }
        strokes.update(dt: Double(dt))
        guideStep()
        for index in pops.indices.reversed() {
            pops[index].life -= dt
            pops[index].entity.position += pops[index].velocity * dt
            pops[index].entity.scale *= max(0, 1 - pops[index].shrink * dt)
            if pops[index].life <= 0 {
                pops[index].entity.removeFromParent()
                pops.remove(at: index)
            }
        }
        deck.show(strokes.groom, "Groomed")
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
            guide.isEnabled = false
            deck.cheer(big: true)
            deck.result = GameResult(game: .brush, score: 100)
        }
    }

    /// The fur-direction guide: honey dots running neck to hips over her back with a chevron at the end, and, while
    /// no finger is down, the brush itself sliding the same way.
    private func guideStep() {
        guard let spine, deck.result == nil else { return }
        let shows = strokes.showsGuide(sinceTouch: Double(sinceTouch))
        guide.isEnabled = shows
        guard shows else {
            if !touching { brush.isEnabled = false }
            return
        }
        let lift = spots.toward * (0.26 * spots.length) + [0, 0.1 * spots.length, 0]
        let direction = simd_normalize(spine.hips - spine.neck)
        let phase = (time * 0.7).truncatingRemainder(dividingBy: 1)
        for (index, dot) in guideDots.enumerated() {
            let along = (Float(index) / Float(guideDots.count) + phase / Float(guideDots.count))
            dot.position = simd_mix(spine.neck, spine.hips, SIMD3(repeating: 0.1 + along * 0.7)) + lift
            let near = abs(along - phase) / 0.2
            dot.scale = SIMD3(repeating: (1.3 - min(near, 1)) * 0.006)
        }
        let align = simd_quatf(from: [1, 0, 0], to: direction)
        for (index, arm) in arrow.enumerated() {
            arm.position = simd_mix(spine.neck, spine.hips, SIMD3(repeating: 0.9)) + lift
            arm.orientation = align * .z(index == 0 ? 0.7 : -0.7)
        }
        if !touching {
            brush.isEnabled = true
            let slide = Float(0.5 - 0.5 * cos(time * 2.2))
            brush.position = simd_mix(spine.neck, spine.hips, SIMD3(repeating: 0.1 + 0.75 * slide)) + lift + [0, 0.05 * spots.length, 0]
            brush.orientation = brushPose
        }
    }

    private func heart(at point: SIMD3<Float>) {
        guard pops.count < 14 else { return }
        let pink = Clay.glow(0xFF7A98, intensity: 1.4)
        let heart = root.group(at: point)
        heart.sphere(0.007, pink, at: [-0.0055, 0.004, 0])
        heart.sphere(0.007, pink, at: [0.0055, 0.004, 0])
        heart.box(0.0105, 0.0105, 0.008, r: 0.002, pink, at: [0, -0.001, 0], rotation: .z(.pi / 4))
        pops.append((heart, [Float.random(in: -0.01...0.01), 0.07, 0], 1.0, 0.9))
    }

    private func spark(at point: SIMD3<Float>) {
        guard pops.count < 14 else { return }
        let bit = root.sphere(0.004, Clay.glow(0xFFE08A, intensity: 4), at: point + [Float.random(in: -0.03...0.03), 0, 0])
        pops.append((bit, [Float.random(in: -0.03...0.03), 0.05, 0], 0.35, 2.6))
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
