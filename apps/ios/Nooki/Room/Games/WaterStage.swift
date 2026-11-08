import FeatureGames
import GamesInterface
import RealityKit
import UIKit

/// Fresh water: hold anywhere to pour from the jug and let go on the line. Past the brim it spills into a puddle;
/// rub the puddle to wipe it up, or drag the bowl to tip some back out. Served, Mochi comes over and drinks.
@MainActor
final class WaterStage: GameStage {
    private enum Grip { case pour, wipe, tip }

    private static let bowlRadius: Float = 0.042
    private static let bowlHeight: Float = 0.026
    private static let floorInside: Float = 0.005
    /// The tip of the jug's spout, in the jug's own space.
    private static let spoutTip: SIMD3<Float> = [0.046, 0.062, 0]

    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private let bowlAt: SIMD3<Float>
    private let water: ModelEntity
    private let jug: Entity
    private let stream: ModelEntity
    private let puddle: ModelEntity
    private let puddleAt: SIMD3<Float>
    private var bowl = WaterBowl()
    private var grip: Grip?
    private var lastWipe: SIMD3<Float>?
    private var flow: Float = 0
    private var sinceTap: Float = 0
    private var flicked = false
    private var served = false
    private var shownHint: String?

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        bowlAt = spots.at(0.02, 0.05)
        puddleAt = bowlAt + spots.toward * 0.07 - spots.right * 0.03

        let bowlGroup = root.group(at: bowlAt)
        bowlGroup.cylinder(Self.bowlHeight, Self.bowlRadius, Clay.matte(0x6F8FB0, roughness: 0.4),
                           at: [0, Self.bowlHeight / 2, 0])
        bowlGroup.cylinder(0.001, Self.bowlRadius - 0.004, Clay.matte(0xFFF3E2, roughness: 0.35),
                           at: [0, Self.bowlHeight + 0.0006, 0])
        // The fill line: a ring of small blue beads inside the rim.
        let lineY = Self.floorInside + Float(WaterBowl.line) * (Self.bowlHeight - Self.floorInside)
        let lineMaterial = Clay.glow(0x3F7FC0, intensity: 0.6)
        for i in 0..<28 {
            let angle = Float(i) / 28 * 2 * .pi
            let r = Self.bowlRadius - 0.0035
            bowlGroup.sphere(0.0011, lineMaterial, at: [r * cos(angle), lineY + 0.0012, r * sin(angle)])
        }
        var waterMaterial = PhysicallyBasedMaterial()
        waterMaterial.baseColor = .init(tint: UIColor(red: 0.56, green: 0.82, blue: 1, alpha: 1))
        waterMaterial.roughness = 0.05
        waterMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        water = bowlGroup.cylinder(1, Self.bowlRadius - 0.0045, waterMaterial, at: [0, Self.floorInside, 0])
        water.isEnabled = false

        // The jug waits up to the left; holding tips it over the bowl (see `draw`).
        jug = root.group(at: bowlAt - spots.right * 0.06 + [0, 0.11, 0])
        jug.cylinder(0.07, 0.024, Clay.matte(0xFFF3E2, roughness: 0.5), at: [0, 0.035, 0])
        jug.box(0.03, 0.012, 0.016, r: 0.004, Clay.matte(0xFFF3E2, roughness: 0.5), at: [0.03, 0.062, 0])
        jug.box(0.008, 0.045, 0.012, r: 0.004, Clay.matte(0xE98A5B), at: [-0.028, 0.04, 0])
        jug.orientation = simd_quatf(from: [1, 0, 0], to: spots.right)
        stream = root.cylinder(1, 0.0025, waterMaterial, at: bowlAt)
        stream.isEnabled = false
        puddle = root.cylinder(0.0012, 1, waterMaterial, at: puddleAt + [0, 0.0006, 0])
        puddle.isEnabled = false

        // Behind the bowl, facing it.
        let seat = spots.at(0, -0.13)
        room.send(to: seat, facing: GameSpots.yaw(from: seat, to: bowlAt), id: "water-watch")
        say(bowl.hint)
    }

    var focus: [SIMD3<Float>] {
        [bowlAt - spots.right * 0.12, bowlAt + spots.right * 0.1, bowlAt + [0, 0.2, 0], puddleAt, spots.at(0, -0.13, up: 0.12)]
    }

    var action: String? { bowl.canServe && grip != .pour && !served ? "Serve" : nil }

    func act() { serve() }

    func began(_ touch: GameTouch) {
        guard !served else { return }
        if bowl.puddle > WaterBowl.dry, let floor = touch.onPlane(y: spots.floor),
           simd_distance(floor, puddleAt) < puddleRadius + 0.03 {
            grip = .wipe
            lastWipe = floor
        } else if bowl.level > 0.05, touch.distance(to: bowlAt + [0, 0.015, 0]) < 0.05 {
            grip = .tip
        } else {
            grip = .pour
        }
    }

    func moved(_ touch: GameTouch) {
        guard grip == .wipe, let floor = touch.onPlane(y: spots.floor) else { return }
        if let lastWipe { bowl.wipe(Double(simd_distance(floor, lastWipe)) * 0.6) }
        lastWipe = floor
        if sinceTap > 0.1 {
            sinceTap = 0
            deck.stroke()
        }
    }

    func ended(_ touch: GameTouch?) {
        let was = grip
        grip = nil
        lastWipe = nil
        // Let go on the line with the floor dry: served.
        if was == .pour, bowl.canServe, bowl.puddle <= WaterBowl.dry, !bowl.isSpilling { serve() }
    }

    func update(_ dt: Float) {
        sinceTap += dt
        flow += ((grip == .pour && !served ? 1 : 0) - flow) * min(1, dt * 6)
        if flow < 0.01 { flow = 0 }
        bowl.pour(flow: Double(flow), dt: Double(dt))
        if grip == .tip { bowl.pourOut(dt: Double(dt)) }
        if flow > 0.1, sinceTap > 0.09 {
            sinceTap = 0
            deck.tap(CGFloat(0.25 + 0.4 * flow))
        }
        if bowl.isOverLine, !flicked {
            flicked = true
            room.walker?.behavior.perform(.flick)
        }
        draw()
        if !served { say(bowl.hint) }
    }

    private var puddleRadius: Float { min(0.075, 0.012 + Float(bowl.puddle).squareRoot() * 0.12) }

    private func draw() {
        let level = Float(bowl.level)
        let surface = Self.floorInside + level * (Self.bowlHeight - Self.floorInside)
        water.isEnabled = level > 0.01
        water.scale = [Self.bowlRadius - 0.0045, max(surface - Self.floorInside, 0.0005), Self.bowlRadius - 0.0045]
        water.position = [0, (surface + Self.floorInside) / 2, 0]
        // The jug glides over the bowl and tips as you hold, its spout kept over the water; the stream falls from that
        // spout to the surface.
        let eased = flow * flow * (3 - 2 * flow)
        let tilt = simd_quatf(angle: -1.0 * eased, axis: [0, 0, 1])
        jug.orientation = simd_quatf(from: [1, 0, 0], to: spots.right) * tilt
        let waiting = bowlAt - spots.right * 0.075 + [0, 0.1, 0]
        let pouring = bowlAt - spots.right * 0.016 + [0, Self.bowlHeight + 0.045, 0]
        let spout = simd_mix(waiting, pouring, SIMD3(repeating: eased))
        jug.position = spout - jug.orientation.act(Self.spoutTip)
        let bottom = SIMD3<Float>(spout.x, bowlAt.y + surface, spout.z)
        let drop = max(spout.y - bottom.y, 0.001)
        let width = 0.0022 * flow + 0.0008
        stream.isEnabled = flow > 0.05
        stream.position = (spout + bottom) / 2
        stream.scale = [width, drop, width]
        stream.orientation = .identity
        puddle.isEnabled = bowl.puddle > WaterBowl.dry / 4
        let r = puddleRadius
        puddle.scale = [r, 0.0012, r]
    }

    private func say(_ text: String) {
        guard text != shownHint else { return }
        shownHint = text
        deck.say(text)
    }

    private func serve() {
        guard bowl.canServe, !served else { return }
        served = true
        grip = nil
        deck.say(bowl.rating == .perfect ? "Perfect!" : bowl.rating == .good ? "Good!" : "A bit much… she drinks anyway",
                 for: 1.6)
        let drink = bowlAt - spots.toward * 0.1
        room.send(to: [drink.x, spots.floor, drink.z], facing: GameSpots.yaw(from: drink, to: bowlAt), id: "water-drink") {
            [weak self] in self?.room.walker?.behavior.perform(.slowBlink)
        }
        deck.result = GameResult.water(bowl)
    }

    func tearDown() {
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
