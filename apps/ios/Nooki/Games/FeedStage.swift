import CoreMotion
import FeatureGames
import RealityKit
import SwiftUI
import UIKit

/// Weigh the food: tap the bowl onto the kitchen scale, press TARE or don't, and pour what her card asks for. The
/// kibble goes in four ways: tip the bag (drag it; tipped fast, a clump drops), a scoop (tap it), one by one (tap
/// the bag), or a shake of the phone. Drag the bowl to tip some back, or tap it for one kibble out. Feed works once
/// the bowl is within tolerance; then Mochi comes and eats.
@MainActor
final class FeedStage: GameStage {
    private enum Grip {
        case bag(start: CGPoint)
        case bowl(start: CGPoint)
        case tare, scoop
    }

    /// One kibble in the air, from `from` to `to`, landing in the bowl (`into`) or back in the bag.
    private struct Flight {
        let entity: ModelEntity
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        var time: Float = 0
        let length: Float
        let grams: Double
        let into: Bool
    }

    private static let platformY: Float = 0.034
    private static let kibbleTones: [UInt32] = [0x8A5528, 0x9E6530, 0x7A4622, 0xB07A3E]
    private static let bowlHeight: Float = 0.03
    private static let bowlRadius: Float = 0.048

    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private let task: FeedTask
    private let name: String
    private var scale = KibbleScale()
    private var rng = SystemRandomNumberGenerator()

    private let scaleAt: SIMD3<Float>
    private let bowlHome: SIMD3<Float>
    private let bagAt: SIMD3<Float>
    private let scoopAt: SIMD3<Float>
    private let tareAt: SIMD3<Float>
    private let bowl: Entity
    private let bag: Entity
    private let tareButton: ModelEntity
    private let display: ModelEntity
    private var displayTexture: TextureResource?
    private var shownText = ""

    private var grip: Grip?
    private var bagAngle: Float = 0
    private var bagWant: Float = 0
    private var bowlTilt: Float = 0
    private var sinceClump: Double = 9
    private var pourDebt: Double = 0
    private var backDebt: Double = 0
    private var flights: [Flight] = []
    /// The kibble resting in the bowl, in the order it landed.
    private var pile: [ModelEntity] = []
    private var bowlMove: (from: SIMD3<Float>, to: SIMD3<Float>, time: Float)?
    private var shown: Double = 0
    private var settle: Float = 0
    private var sinceTap: Float = 0
    private var eating: Float?
    /// The kibble in the bowl when dinner was served.
    private var served = 0
    private var started = false

    private let motion = CMMotionManager()
    private var sinceShake: Float = 1

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        task = FeedTask(full: room.director?.needs?.full ?? 0.5)
        name = CatProfile.name()
        scaleAt = spots.at(0, 0.03)
        bowlHome = spots.at(-0.15, 0.07)
        bagAt = spots.at(0.16, -0.02)
        scoopAt = spots.at(0.14, 0.12)

        // The scale: a cream shell, a steel platform, a green display and the TARE button toward the camera.
        let base = root.group(at: scaleAt, rotation: simd_quatf(from: [0, 0, 1], to: spots.toward))
        base.box(0.15, 0.026, 0.19, r: 0.012, Clay.matte(0xFFF3E2, roughness: 0.45), at: [0, 0.013, 0])
        var steel = PhysicallyBasedMaterial()
        steel.baseColor = .init(tint: UIColor(red: 0.84, green: 0.86, blue: 0.87, alpha: 1))
        steel.metallic = 0.65
        steel.roughness = 0.28
        base.cylinder(0.005, 0.064, steel, at: [0, Self.platformY - 0.0025, -0.015])
        base.box(0.094, 0.006, 0.04, r: 0.004, Clay.matte(0x3A3530, roughness: 0.5), at: [0, 0.027, 0.075])
        display = base.model(.generatePlane(width: 0.08, depth: 0.03), UnlitMaterial(color: UIColor(red: 0.72, green: 0.79, blue: 0.64, alpha: 1)),
                             at: [-0.004, 0.0305, 0.075])
        tareButton = base.cylinder(0.005, 0.0085, Clay.matte(0xE0554A, roughness: 0.5), at: [-0.058, 0.028, 0.072])
        tareAt = base.convert(position: [-0.058, 0.028, 0.072], to: room.pivot)

        // The bowl, waiting beside it.
        bowl = root.group(at: bowlHome)
        bowl.cylinder(Self.bowlHeight, Self.bowlRadius, Clay.matte(0x6F8FB0, roughness: 0.4), at: [0, Self.bowlHeight / 2, 0])
        bowl.cylinder(0.001, Self.bowlRadius - 0.004, Clay.matte(0xFFF3E2, roughness: 0.35), at: [0, Self.bowlHeight + 0.0006, 0])

        // The bag of kibble, standing, tipped about its mouth toward the scale.
        bag = root.group(at: bagAt + [0, 0.15, 0])
        bag.box(0.1, 0.15, 0.07, r: 0.014, Clay.matte(0xD9B48A, roughness: 0.9), at: [0, -0.075, 0])
        bag.box(0.07, 0.07, 0.002, r: 0.001, Clay.matte(0xE0554A, roughness: 0.8), at: [0, -0.085, 0.036])
        bag.box(0.094, 0.004, 0.064, r: 0.002, Clay.matte(0x5A3A22, roughness: 1), at: [0, -0.002, 0])
        bag.orientation = simd_quatf(from: [0, 0, 1], to: spots.toward)

        // The scoop, in front.
        let scoop = root.group(at: scoopAt)
        scoop.cylinder(0.02, 0.018, Clay.matte(0xE98A5B, roughness: 0.5), at: [0, 0.01, 0])
        scoop.box(0.05, 0.008, 0.01, r: 0.004, Clay.matte(0xE98A5B, roughness: 0.5), at: [0.04, 0.012, 0])

        let seat = spots.at(0, -0.17)
        room.send(to: seat, facing: GameSpots.yaw(from: seat, to: scaleAt), id: "feed-watch")
        deck.say("\(name) needs \(task.target) g. Tap the bowl onto the scale")
        drawDisplay(force: true)

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1 / 30
            motion.startDeviceMotionUpdates()
        }
    }

    var focus: [SIMD3<Float>] {
        [bowlHome - spots.right * 0.04, bagAt + spots.right * 0.05 + [0, 0.16, 0], scaleAt + spots.toward * 0.1,
         spots.at(0, -0.17, up: 0.1)]
    }

    var action: String? { started && eating == nil ? "Feed" : nil }

    /// Where the bowl's food sits: on the platform or at home.
    private var bowlAt: SIMD3<Float> { bowl.position }
    private var onScaleSpot: SIMD3<Float> { scaleAt - spots.toward * 0.015 + [0, Self.platformY, 0] }

    func began(_ touch: GameTouch) {
        guard eating == nil else { return }
        if touch.distance(to: tareAt) < 0.022 {
            grip = .tare
        } else if touch.distance(to: bowlAt + [0, 0.015, 0]) < 0.06 {
            grip = .bowl(start: touch.point)
        } else if touch.distance(to: scoopAt + [0, 0.01, 0]) < 0.04 {
            grip = .scoop
        } else if touch.distance(to: bagAt + [0, 0.08, 0]) < 0.08 {
            grip = .bag(start: touch.point)
        }
    }

    func moved(_ touch: GameTouch) {
        switch grip {
        case .bag(let start):
            // Dragging toward the scale (left) tips the bag further.
            let pulled = max(0, start.x - touch.point.x) + max(0, touch.point.y - start.y) * 0.5
            bagWant = min(2.2, Float(pulled / 90))
        case .bowl(let start):
            // Lifted toward the bag, the bowl tips some kibble back.
            let pushed = max(0, touch.point.x - start.x)
            bowlTilt = min(1.6, Float(pushed / 80))
        default: break
        }
    }

    func ended(_ touch: GameTouch?) {
        defer {
            grip = nil
            bagWant = 0
            bowlTilt = 0
        }
        guard let grip, eating == nil else { return }
        let moved = touch.map { touch -> CGFloat in
            switch grip {
            case .bag(let start), .bowl(let start): hypot(touch.point.x - start.x, touch.point.y - start.y)
            default: 0
            }
        } ?? 0
        switch grip {
        case .tare:
            scale.pressTare()
            tareButton.position.y = 0.026
            deck.tap(0.8)
            settle = 0.15
            started = true
            if scale.bowlOnScale { deck.say("\(name) needs \(task.target) g. Now pour", for: 3) }
        case .bowl where moved < 14:
            if !scale.bowlOnScale {
                moveBowl(to: onScaleSpot)
                scale.putBowl(onScale: true)
                settle = 0.4
                started = true
                deck.say("Press TARE to zero it, or don't, and pour", for: 3)
            } else if scale.food >= KibbleScale.kibbleGrams {
                takeOne()
            }
        case .scoop:
            let grams = KibblePour.scoop(using: &rng)
            for _ in 0..<Int((grams / KibbleScale.kibbleGrams).rounded()) { pour(from: scoopAt + [0, 0.05, 0], spread: 0.6) }
            started = true
            deck.tap()
        case .bag where moved < 14:
            pour(from: mouth, spread: 0.2)
            started = true
            deck.tap(0.4)
        default: break
        }
    }

    func act() {
        guard eating == nil else { return }
        switch task.check(food: scale.food) {
        case .ready(let perfect):
            deck.say(perfect ? "Exactly \(task.target) g!" : "\(Int(scale.food.rounded())) g: close enough", for: 1.5)
            serve()
        default:
            deck.say(task.advice(food: scale.food), for: 2.2)
            deck.tap(0.3)
        }
    }

    func update(_ dt: Float) {
        sinceTap += dt
        sinceClump += Double(dt)
        sinceShake += dt
        tareButton.position.y += (0.028 - tareButton.position.y) * min(1, dt * 10)
        updateBag(dt)
        updateBowl(dt)
        shakeCheck()
        fly(dt)
        updateDisplay(dt)
        if let time = eating {
            eat(time: time + dt)
        }
    }

    // MARK: - Pouring

    private var mouth: SIMD3<Float> { bag.convert(position: [0, 0, 0], to: room.pivot) }

    private func updateBag(_ dt: Float) {
        let before = bagAngle
        bagAngle += (bagWant - bagAngle) * min(1, dt * 8)
        bag.orientation = simd_quatf(from: [0, 0, 1], to: spots.toward) * simd_quatf(angle: bagAngle, axis: [0, 0, 1])
        let turnRate = Double(abs(bagAngle - before) / max(dt, 1e-3))
        let flow = KibblePour.flow(angle: Double(bagAngle))
        if flow > 0 {
            started = true
            pourDebt += flow * Double(dt)
            while pourDebt >= KibbleScale.kibbleGrams {
                pourDebt -= KibbleScale.kibbleGrams
                pour(from: mouth, spread: 0.4)
            }
            if sinceTap > 0.08 {
                sinceTap = 0
                deck.tap(CGFloat(0.2 + flow / 40))
            }
        }
        if let clump = KibblePour.clump(turnRate: turnRate, angle: Double(bagAngle), sinceLast: sinceClump, using: &rng) {
            sinceClump = 0
            for _ in 0..<Int((clump / KibbleScale.kibbleGrams).rounded()) { pour(from: mouth, spread: 0.9) }
            deck.say("Whoops, a clump!", for: 1.4)
            deck.thump()
        }
    }

    private func updateBowl(_ dt: Float) {
        if var move = bowlMove {
            move.time = min(1, move.time + dt * 2.5)
            let s = move.time * move.time * (3 - 2 * move.time)
            bowl.position = simd_mix(move.from, move.to, SIMD3(repeating: s)) + [0, 0.05 * sin(s * .pi), 0]
            bowlMove = move.time < 1 ? move : nil
        }
        let tilt = bowlTilt
        bowl.orientation = simd_quatf(angle: -tilt * 0.6, axis: simd_normalize(spots.toward))
        let back = KibblePour.back(tilt: Double(tilt))
        guard back > 0, scale.food > 0 else { return }
        backDebt += back * Double(dt)
        while backDebt >= KibbleScale.kibbleGrams, scale.food >= KibbleScale.kibbleGrams {
            backDebt -= KibbleScale.kibbleGrams
            takeOne()
        }
    }

    /// A shake of the phone loosens a kibble or three from the bag.
    private func shakeCheck() {
        guard let acceleration = motion.deviceMotion?.userAcceleration, sinceShake > 0.25 else { return }
        let strength = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
        guard strength > 1.2 else { return }
        sinceShake = 0
        started = true
        let grams = KibblePour.shake(strength: min((strength - 1.2) / 1.5, 1), using: &rng)
        for _ in 0..<Int((grams / KibbleScale.kibbleGrams).rounded()) { pour(from: mouth, spread: 0.3) }
        deck.tap(0.7)
    }

    private func moveBowl(to target: SIMD3<Float>) {
        bowlMove = (bowl.position, target, 0)
    }

    /// Sends one kibble from `start` toward the bowl.
    private func pour(from start: SIMD3<Float>, spread: Float) {
        guard flights.count < 90 else { return }
        let kibble = root.sphere(0.0042, Clay.matte(Self.kibbleTones.randomElement() ?? 0x8A5528, roughness: 0.75),
                                 at: start, scale: [1, 0.6, 1])
        let slot = pileSlot(pile.count + flights.filter(\.into).count)
        flights.append(Flight(entity: kibble, from: start + SIMD3(Float.random(in: -0.01...0.01) * spread, 0, 0),
                              to: slot, length: Float.random(in: 0.28...0.42), grams: KibbleScale.kibbleGrams, into: true))
    }

    /// Takes the top kibble out of the bowl, back to the bag.
    private func takeOne() {
        guard let kibble = pile.popLast() else { return }
        scale.add(-KibbleScale.kibbleGrams)
        settle = 0.25
        let start = kibble.position(relativeTo: root)
        kibble.removeFromParent()
        root.addChild(kibble)
        kibble.position = start
        flights.append(Flight(entity: kibble, from: start, to: mouth, length: 0.35, grams: 0, into: false))
        deck.tap(0.3)
    }

    private func fly(_ dt: Float) {
        for index in flights.indices.reversed() {
            flights[index].time += dt
            let flight = flights[index]
            let u = min(1, flight.time / flight.length)
            let arc: Float = flight.into ? 0.03 : 0.06
            flight.entity.position = simd_mix(flight.from, flight.to, SIMD3(repeating: u)) + [0, arc * sin(u * .pi), 0]
            guard u >= 1 else { continue }
            flights.remove(at: index)
            if flight.into {
                // Settles into the pile, which rides with the bowl from now on.
                let local = bowl.convert(position: flight.to, from: root)
                flight.entity.removeFromParent()
                bowl.addChild(flight.entity)
                flight.entity.position = local
                pile.append(flight.entity)
                scale.add(flight.grams)
                settle = 0.25
            } else {
                flight.entity.removeFromParent()
            }
        }
    }

    /// Where the `index`th kibble rests in the bowl, in `root`'s space: a spiral that rises as it fills.
    private func pileSlot(_ index: Int) -> SIMD3<Float> {
        let layer = index / 40
        let k = Float(index % 40)
        let angle = k * 2.4
        let r = (Self.bowlRadius - 0.01) * (k / 40).squareRoot()
        let local = SIMD3<Float>(r * cos(angle), 0.009 + Float(layer) * 0.0045 + (1 - r / Self.bowlRadius) * 0.002, r * sin(angle))
        let target = bowlMove?.to ?? bowl.position
        return target + local
    }

    // MARK: - The display

    private func updateDisplay(_ dt: Float) {
        settle = max(0, settle - dt)
        let reading = Double(scale.reading)
        // A real scale wobbles a gram or two before it settles.
        shown = settle > 0 ? reading + Double(Int.random(in: -1...1)) : reading
        drawDisplay(force: false)
    }

    private func drawDisplay(force: Bool) {
        let text = "\(Int(shown))"
        guard force || text != shownText else { return }
        shownText = text
        let tared = scale.isTared
        let renderer = ImageRenderer(content:
            ZStack(alignment: .trailing) {
                Color(red: 0.72, green: 0.79, blue: 0.64)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    if tared { Text("→0←").font(.system(size: 18, weight: .bold)).padding(.trailing, 8) }
                    Text(text).font(.system(size: 64, weight: .bold, design: .monospaced))
                    Text("g").font(.system(size: 26, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.13, green: 0.19, blue: 0.11))
                .padding(.trailing, 14)
            }
            .frame(width: 256, height: 96))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return }
        if let displayTexture {
            try? displayTexture.replace(withImage: image, options: .init(semantic: .color))
        } else if let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            displayTexture = texture
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            display.model?.materials = [material]
        }
    }

    // MARK: - Dinner

    private func serve() {
        eating = 0
        served = pile.count
        let result = GameResult.feed(target: task.target, food: scale.food)
        scale.putBowl(onScale: false)
        let dinner = spots.at(-0.02, -0.11)
        moveBowl(to: dinner)
        let seat = dinner - spots.right * 0.09
        room.send(to: [seat.x, spots.floor, seat.z], facing: GameSpots.yaw(from: seat, to: dinner), id: "feed-eat")
        deck.result = result
    }

    /// She eats: the pile goes down over a few seconds once she is at the bowl.
    private func eat(time: Float) {
        eating = time
        guard room.walker?.moving == false, time > 1 else { return }
        let left = Int(Float(served) * max(0, 1 - (time - 1) / 3.6))
        while pile.count > left { pile.removeLast().removeFromParent() }
    }

    func tearDown() {
        motion.stopDeviceMotionUpdates()
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
