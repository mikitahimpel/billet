import FeatureGames
import GamesInterface
import RealityKit
import UIKit

/// Fresh water: hold anywhere to pour from the jug and let go on the line. The jug stops by itself just past the line, so
/// the bowl never spills; let go in the band or tap Serve and Mochi, sitting behind the bowl, drinks.
@MainActor
final class WaterStage: GameStage {
    private static let bowlRadius: Float = 0.042
    private static let bowlHeight: Float = 0.026
    private static let floorInside: Float = 0.005
    /// The water's thickness: a skin on the surface, lifted by the level.
    private static let skin: Float = 0.0008
    /// How high the mat's top lies over the floor, where the puddle spreads.
    private static let matTop: Float = 0.0075
    /// The tip of the jug's spout, in the jug's own space.
    private static let spoutTip: SIMD3<Float> = [0.046, 0.062, 0]

    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private let bowlAt: SIMD3<Float>
    private let water: ModelEntity
    /// The ring where the stream lands, widening while it pours.
    private let splash: ModelEntity
    /// The level as drawn, eased toward the bowl's.
    private var shown: Float = 0
    private var clock: Float = 0
    private let jug: Entity
    private let stream: ModelEntity
    private var bowl = WaterBowl()
    private var holding = false
    private var flow: Float = 0
    private var sinceTap: Float = 0
    private var served = false
    private var drinking: Float = 0
    private var shownHint: String?
    private let puddle: ModelEntity
    private let cloth: ModelEntity
    private var shownPuddle: Float = 0
    /// Where the finger is on the mat, while it wipes.
    private var finger: SIMD3<Float>?
    private var clothAt: SIMD3<Float>
    private var sinceStroke: Float = 0
    /// Seconds into the Clean up button's wipe, while it runs.
    private var assisted: Float?
    private var messSeen = false
    /// Whether the water has reached the band once: she hops for it the first time.
    private var readySeen = false

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        bowlAt = spots.at(0, 0.02)

        let bowlGroup = root.group(at: bowlAt)
        if let mesh = BowlMesh.make(outer: Self.bowlRadius, inner: Self.bowlRadius - 0.0045, height: Self.bowlHeight,
                                    floor: Self.floorInside) {
            let body = ModelEntity(mesh: mesh, materials: [Clay.matte(0x6F8FB0, roughness: 0.4),
                                                           Clay.matte(0xFFF3E2, roughness: 0.35)])
            bowlGroup.addChild(body)
        }
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
        water = bowlGroup.cylinder(Self.skin, Self.bowlRadius - 0.0055, waterMaterial, at: [0, Self.floorInside, 0])
        water.isEnabled = false
        splash = bowlGroup.cylinder(Self.skin, 0.006, Clay.glow(0xE6F4FF, intensity: 0.5), at: [0, Self.floorInside, 0])
        splash.isEnabled = false

        // The jug waits up to the left; holding tips it over the bowl (see `draw`).
        jug = root.group(at: bowlAt - spots.right * 0.06 + [0, 0.11, 0])
        jug.cylinder(0.07, 0.024, Clay.matte(0xFFF3E2, roughness: 0.5), at: [0, 0.035, 0])
        jug.box(0.03, 0.012, 0.016, r: 0.004, Clay.matte(0xFFF3E2, roughness: 0.5), at: [0.03, 0.062, 0])
        jug.box(0.008, 0.045, 0.012, r: 0.004, Clay.matte(0xE98A5B), at: [-0.028, 0.04, 0])
        jug.orientation = simd_quatf(from: [1, 0, 0], to: spots.right)
        stream = root.cylinder(1, 0.0025, waterMaterial, at: bowlAt)
        stream.isEnabled = false

        var puddleMaterial = waterMaterial
        puddleMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        puddle = root.cylinder(Self.skin, 1, puddleMaterial, at: bowlAt + [0, Self.matTop, 0])
        puddle.isEnabled = false
        cloth = root.box(0.05, 0.014, 0.034, r: 0.006, Clay.matte(0xF2C14E, roughness: 0.9), at: bowlAt)
        cloth.isEnabled = false
        clothAt = bowlAt

        // Behind the bowl, facing the player.
        let seat = spots.at(0, -0.13)
        root.contactBlob(at: bowlAt, width: 0.15, depth: 0.11)
        root.contactBlob(at: seat, width: 0.24, depth: 0.16)
        room.send(to: seat, facing: spots.facingPlayer, id: "water-watch")
        say(hint)
    }

    var seat: SIMD3<Float>? { spots.at(0, -0.13) }

    var focus: [SIMD3<Float>] {
        [bowlAt - spots.right * 0.12, bowlAt + spots.right * 0.1, bowlAt + [0, 0.2, 0], bowlAt + spots.toward * 0.08, spots.at(0, -0.13, up: 0.12), spots.at(0, -0.13, up: 0.2)]
    }

    var action: String? { bowl.canServe && !holding && !served && bowl.phase != .settling ? "Serve" : nil }

    func act() { serve() }

    var assist: String? { bowl.phase == .messy && !served && !holding && assisted == nil ? "Clean up" : nil }

    func assistAct() {
        guard bowl.phase == .messy, assisted == nil else { return }
        if UIAccessibility.isReduceMotionEnabled {
            bowl.wipe(WaterBowl.puddleCap)
        } else {
            assisted = 0
        }
    }

    private var puddleCenter: SIMD3<Float> { bowlAt + spots.toward * 0.075 + [0, Self.matTop, 0] }
    private var puddleRadius: Float { 0.025 + 0.1 * (shownPuddle / Float(WaterBowl.puddleCap)).squareRoot() }

    var cue: GameCue? {
        guard !served else { return nil }
        if bowl.phase == .messy {
            let c = puddleCenter
            return GameCue(step: 2, gesture: .drag(to: c + spots.right * 0.05), at: c - spots.right * 0.05)
        }
        guard !bowl.canServe else { return nil }
        return GameCue(step: 1, gesture: .hold, at: jug.position + [0, 0.035, 0])
    }

    var glance: CGSize? { served && drinking.truncatingRemainder(dividingBy: 2.6) < 1.8 ? CGSize(width: 0, height: 120) : nil }

    func began(_ touch: GameTouch) {
        guard !served else { return }
        if bowl.phase == .messy {
            finger = touch.onPlane(y: bowlAt.y + Self.matTop)
        } else if bowl.phase == .pouring {
            holding = true
        }
    }

    func moved(_ touch: GameTouch) {
        if bowl.phase == .messy { finger = touch.onPlane(y: bowlAt.y + Self.matTop) }
    }

    func ended(_ touch: GameTouch?) {
        let was = holding
        holding = false
        finger = nil
        // Let go on the line: served. Past the band or in a puddle there is a mess to see to first.
        if was, bowl.canServe, !bowl.isOverLine, bowl.phase == .pouring, !served { serve() }
    }

    func update(_ dt: Float) {
        deck.show(min(bowl.level / WaterBowl.line, 1), "Water level")
        sinceTap += dt
        if served { drinking += dt }
        flow += ((holding && !served && !bowl.isFlooded ? 1 : 0) - flow) * min(1, dt * 6)
        if flow < 0.01 { flow = 0 }
        bowl.pour(flow: Double(flow), dt: Double(dt))
        if bowl.canServe, !served, !readySeen {
            readySeen = true
            room.walker?.hop()
            deck.tap(1)
        }
        if flow > 0.1, sinceTap > 0.09 {
            sinceTap = 0
            deck.tap(CGFloat(0.25 + 0.4 * flow))
        }
        tidy(dt)
        draw(dt)
        if !served { say(hint) }
    }

    /// The puddle spreads with the spill; a finger (or the Clean up button) drags the cloth over it, and what the cloth
    /// covers is taken up. Once it is dry the bowl drops back to the band.
    private func tidy(_ dt: Float) {
        let calm = UIAccessibility.isReduceMotionEnabled
        sinceStroke += dt
        let messy = bowl.phase == .messy
        if messy, !messSeen {
            messSeen = true
            deck.thump()
            room.react(toMess: true, seat: spots.at(0, -0.13), back: spots.at(0, -0.19), facing: spots.facingPlayer, id: "water-watch")
        }
        var target: SIMD3<Float>? = finger
        if let t = assisted {
            assisted = t + dt
            let u = min(t / 1.1, 1)
            target = puddleCenter + spots.right * (sin(u * 3 * .pi * 2) * puddleRadius * 0.8) + [0, 0.006, 0]
            if u >= 1 {
                assisted = nil
                bowl.wipe(WaterBowl.puddleCap)
            }
        }
        if messy, let target {
            let step = simd_length(target - clothAt)
            let inside = simd_length((target - puddleCenter) * [1, 0, 1]) < puddleRadius + 0.02
            clothAt = simd_mix(clothAt, target, SIMD3(repeating: min(1, dt * 18)))
            if inside, step < 0.2 {
                let amount = Double(step) * 4.5
                if assisted != nil { bowl.wipe(Double(dt) / 1.1 * WaterBowl.puddleCap) } else { bowl.wipe(amount) }
                if step > 0.0008, sinceStroke > 0.12 {
                    sinceStroke = 0
                    deck.stroke()
                }
            }
        } else if messy {
            let rest = puddleCenter + spots.right * (puddleRadius + 0.04) + [0, 0.006, 0]
            clothAt = simd_mix(clothAt, rest, SIMD3(repeating: min(1, dt * 6)))
        }
        if messSeen, bowl.phase == .settling, shownPuddle <= 0.01 {
            bowl.settle(dt: Double(dt))
        }
        if bowl.phase == .pouring, bowl.isSpotless, messSeen, !served {
            messSeen = false
            deck.say("Spotless!", for: 1.4)
            deck.cheer()
            room.react(toMess: false, seat: spots.at(0, -0.13), back: spots.at(0, -0.19), facing: spots.facingPlayer, id: "water-watch")
        }
        shownPuddle += (Float(bowl.puddle) - shownPuddle) * min(1, dt * (calm ? 30 : 7))
        puddle.isEnabled = shownPuddle > Float(WaterBowl.dry) / 2
        puddle.position = puddleCenter
        puddle.scale = [puddleRadius, Self.skin, puddleRadius * 0.8]
        cloth.isEnabled = messy
        cloth.position = clothAt
        cloth.orientation = simd_quatf(from: [1, 0, 0], to: spots.right)
    }

    private func draw(_ dt: Float) {
        // She drinks the level down a little while she is served.
        let drunk = served ? 1 - 0.4 * min(drinking / 5, 1) : 1
        shown += (Float(bowl.level) * drunk - shown) * min(1, dt * 9)
        clock += dt
        let level = shown
        let calm = UIAccessibility.isReduceMotionEnabled
        // The surface rides on the level; while it pours it trembles a hair.
        let tremble = calm ? 0 : sin(clock * 22) * 0.00035 * flow
        let surface = Self.floorInside + level * (Self.bowlHeight - Self.floorInside)
        water.isEnabled = level > 0.01
        water.position = [0, surface + tremble, 0]
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
        splash.isEnabled = flow > 0.05 && water.isEnabled
        if splash.isEnabled {
            let spread = calm ? 1 : 1 + 0.8 * (clock * 3).truncatingRemainder(dividingBy: 1)
            splash.scale = [0.006 * spread, Self.skin, 0.006 * spread]
            splash.position = [spout.x - bowlAt.x, surface + Self.skin, spout.z - bowlAt.z]
        }
    }

    private var hint: String {
        switch bowl.phase {
        case .messy: return "Wipe up the puddle, or serve it as it is"
        case .settling: return "Nearly dry"
        case .pouring: break
        }
        if bowl.isOverLine { return holding ? "Careful, it's spilling over" : "Tap Serve" }
        if bowl.canServe { return holding ? "Right there. Let go" : "Right there. Tap Serve" }
        return bowl.level < 0.05 ? "Hold to pour, stop on the blue line" : "A little more"
    }

    private func say(_ text: String) {
        guard text != shownHint else { return }
        shownHint = text
        deck.say(text)
    }

    private func serve() {
        guard bowl.canServe, !served, bowl.phase != .settling else { return }
        served = true
        finger = nil
        assisted = nil
        holding = false
        if bowl.phase == .messy {
            deck.say("A little messy", for: 1.6)
            deck.thump()
        } else {
            deck.say(bowl.isSpotless ? "Spotless!" : bowl.rating == .perfect ? "Perfect!" : "Good!", for: 1.6)
            deck.cheer(big: true)
        }
        deck.result = GameResult.water(bowl)
    }

    func tearDown() {
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
