import FeatureGames
import GamesInterface
import ProfileInterface
import RealityKit
import SwiftUI
import UIKit

/// Fill her bowl: hold anywhere and the bag tips over it; let go and it stops. A ring of beads across the bowl's front
/// fills with the kibble, a green zone on it is the portion her card asks for, and the bag stops by itself at the zone's
/// far end, so nothing overshoots. Once the bowl is in the zone, Feed serves it and she eats, looking up at the player.
@MainActor
final class FeedStage: GameStage {
    /// One kibble in the air, from `from` into the bowl at `to`.
    private struct Flight {
        let entity: ModelEntity
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        var time: Float
        let length: Float
    }

    private static let kibbleTones: [UInt32] = [0x8A5528, 0x9E6530, 0x7A4622, 0xB07A3E]
    private static let bowlHeight: Float = 0.03
    private static let bowlRadius: Float = 0.05
    private static let ringRadius: Float = 0.074
    private static let beads = 36
    /// Grams one kibble on screen stands for.
    private static let piece: Double = 1
    /// How long a touch has to rest before the bag tips, so a brush of the screen pours nothing.
    private static let grace: Float = 0.1

    private let room: CatRoom
    private let deck: GameDeck
    private let spots: GameSpots
    private let root: Entity
    private let task: FeedTask
    private let name: String

    private let bowlAt: SIMD3<Float>
    private let bagRest: SIMD3<Float>
    private let bagPour: SIMD3<Float>
    private let bowl: Entity
    private let bag: Entity
    private var ring: [ModelEntity] = []
    private let materials: (empty: PhysicallyBasedMaterial, filled: PhysicallyBasedMaterial, zone: PhysicallyBasedMaterial,
                            zoneFilled: PhysicallyBasedMaterial)
    private var shownBeads = -1

    private var food: Double = 0
    private var holding: Float?
    private var tip: Float = 0
    private var debt: Double = 0
    private var flights: [Flight] = []
    private var pile: [ModelEntity] = []
    private var sinceTap: Float = 0
    private var capped = false
    private var served: Float?
    private var servedPile = 0
    private var shownHint = ""

    /// The most the bowl takes: the far end of the zone.
    private var cap: Double { Double(task.target + task.tolerance) }

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        task = FeedTask(full: room.director?.needs?.full ?? 0.5)
        name = CatProfile.name()
        bowlAt = spots.at(0, 0.02)
        bagRest = spots.at(0.2, -0.05, up: 0.13)
        bagPour = bowlAt + spots.right * 0.045 + [0, 0.115, 0]

        var empty = Clay.matte(0xFFF3E2, roughness: 0.5)
        empty.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        materials = (empty, Clay.matte(0xF2A65E, roughness: 0.4), Clay.matte(0xA9C27E, roughness: 0.5),
                     Clay.matte(0x6F8A4E, roughness: 0.4))

        bowl = root.group(at: bowlAt)
        bowl.cylinder(0.006, Self.bowlRadius + 0.004, Clay.matte(0xD8653F, roughness: 0.4), at: [0, 0.003, 0])
        bowl.cylinder(Self.bowlHeight - 0.006, Self.bowlRadius, Clay.matte(0xE98A5B, roughness: 0.4),
                      at: [0, 0.006 + (Self.bowlHeight - 0.006) / 2, 0])
        bowl.cylinder(0.004, Self.bowlRadius + 0.003, Clay.matte(0xFFF3E2, roughness: 0.35), at: [0, Self.bowlHeight - 0.002, 0])
        bowl.cylinder(0.001, Self.bowlRadius - 0.006, Clay.matte(0x7A4A2A, roughness: 0.9), at: [0, Self.bowlHeight + 0.0004, 0])

        // The bag stands on the floor by its mouth's pivot, kraft paper with a cream label and a paw.
        bag = root.group(at: bagRest)
        bag.box(0.085, 0.13, 0.05, r: 0.012, Clay.matte(0xC96F4A, roughness: 0.85), at: [0, -0.065, 0])
        bag.box(0.085, 0.014, 0.036, r: 0.005, Clay.matte(0xA8573A, roughness: 0.9), at: [0, -0.004, 0])
        bag.box(0.052, 0.056, 0.002, r: 0.008, Clay.matte(0xFFF3E2, roughness: 0.7), at: [0, -0.07, 0.026])
        bag.sphere(0.0085, Clay.matte(0xC96F4A), at: [0, -0.078, 0.0275], scale: [1.2, 1, 0.3])
        for x: Float in [-0.0135, -0.0045, 0.0045, 0.0135] {
            bag.sphere(0.0042, Clay.matte(0xC96F4A), at: [x, -0.063 + (abs(x) < 0.01 ? 0.004 : 0), 0.0275], scale: [1, 1, 0.3])
        }
        bag.orientation = simd_quatf(from: [0, 0, 1], to: spots.toward)

        buildRing()
        let seat = spots.at(0, -0.13)
        room.send(to: seat, facing: spots.facingPlayer, id: "feed-watch")
        deck.say("Hold to pour \(name)'s \(task.target) g, stop in the green")
        drawRing()
    }

    var focus: [SIMD3<Float>] {
        [bowlAt - spots.right * 0.1, bagRest + spots.right * 0.05 + [0, 0.02, 0], bowlAt + spots.toward * 0.08,
         spots.at(0, -0.13, up: 0.1)]
    }

    var action: String? { served == nil && isReady ? "Feed" : nil }

    var cue: GameCue? {
        guard served == nil, !isReady, food == 0 else { return nil }
        return GameCue(step: 0, gesture: .hold, at: bagRest + [0, -0.06, 0])
    }

    /// Looks down at the bowl for a bite, then up at the player.
    var glance: CGSize? {
        guard let served else { return nil }
        return served.truncatingRemainder(dividingBy: 2.6) < 1.8 ? CGSize(width: 0, height: 120) : nil
    }

    private var isReady: Bool {
        if case .ready = task.check(food: food) { return true }
        return false
    }

    // MARK: - Touch

    func began(_ touch: GameTouch) {
        guard served == nil else { return }
        holding = 0
    }

    func moved(_ touch: GameTouch) {}

    func ended(_ touch: GameTouch?) { holding = nil }

    func act() {
        guard served == nil, isReady else { return }
        serve()
    }

    // MARK: - Frame

    func update(_ dt: Float) {
        sinceTap += dt
        if let held = holding { holding = held + dt }
        let pouring = served == nil && !capped && (holding ?? 0) > Self.grace
        tip += ((pouring ? 1 : 0) - tip) * min(1, dt * 7)
        drawBag()
        if pouring, tip > 0.85 { pourFlow(dt) }
        fly(dt)
        if let time = served { eat(time + dt) }
        drawRing()
        deck.show(min(food / Double(max(task.target, 1)), 1), "Bowl", detail: "\(Int(food.rounded())) / \(task.target) g")
        if served == nil { say(hint) }
    }

    private var hint: String {
        if capped { return "That's the line. Tap Feed" }
        switch task.check(food: food) {
        case .ready: return "Right there. Let go, tap Feed"
        case .tooLittle(let grams): return food < 1 ? "Hold to pour \(name)'s \(task.target) g, stop in the green" : "\(grams) g to go"
        case .tooMuch: return "That's the line. Tap Feed"
        }
    }

    private func say(_ text: String) {
        guard text != shownHint else { return }
        shownHint = text
        deck.say(text)
    }

    private func pourFlow(_ dt: Float) {
        let held = Double(holding ?? 0)
        // Quicker the longer it is held, slower toward the end so the line is easy to stop on.
        let rate = (9 + min(held, 2) * 5) * min(1, max((cap - food) / 9, 0.3))
        debt += rate * Double(dt)
        while debt >= Self.piece, food + Double(flights.count) < cap {
            debt -= Self.piece
            drop()
        }
        if food + Double(flights.count) >= cap, !capped {
            capped = true
            debt = 0
            deck.thump()
        }
        if sinceTap > 0.08 {
            sinceTap = 0
            deck.tap(CGFloat(0.25 + min(rate, 20) / 40))
        }
    }

    private func drawBag() {
        let s = tip * tip * (3 - 2 * tip)
        bag.position = simd_mix(bagRest, bagPour, SIMD3(repeating: s))
        bag.orientation = simd_quatf(from: [0, 0, 1], to: spots.toward) * simd_quatf(angle: 1.55 * s, axis: [0, 0, 1])
    }

    private var mouth: SIMD3<Float> { bag.position }

    private func drop() {
        let kibble = root.sphere(0.0052, Clay.matte(Self.kibbleTones.randomElement() ?? 0x8A5528, roughness: 0.75),
                                 at: mouth, scale: [1, 0.65, 1])
        let slot = slot(pile.count + flights.count)
        flights.append(Flight(entity: kibble, from: mouth + spots.right * Float.random(in: -0.004...0.004), to: slot, time: 0,
                              length: Float.random(in: 0.22...0.32)))
    }

    private func fly(_ dt: Float) {
        for index in flights.indices.reversed() {
            flights[index].time += dt
            let flight = flights[index]
            let u = min(1, flight.time / flight.length)
            flight.entity.position = simd_mix(flight.from, flight.to, SIMD3(repeating: u * u))
            guard u >= 1 else { continue }
            flights.remove(at: index)
            let local = bowl.convert(position: flight.to, from: root)
            flight.entity.removeFromParent()
            bowl.addChild(flight.entity)
            flight.entity.position = local
            pile.append(flight.entity)
            food += Self.piece
        }
    }

    /// Where the `index`th kibble rests in the bowl, in `root`'s space: a spiral that rises as it fills.
    private func slot(_ index: Int) -> SIMD3<Float> {
        let layer = index / 28
        let k = Float(index % 28)
        let r = (Self.bowlRadius - 0.012) * (k / 28).squareRoot()
        let local = SIMD3<Float>(r * cos(k * 2.4), Self.bowlHeight - 0.004 + Float(layer) * 0.0042, r * sin(k * 2.4))
        return bowlAt + local
    }

    // MARK: - The ring

    /// A row of beads across the bowl's front, from her left to her right: empty, filled with the pour, and green over
    /// the zone with a taller one at the portion itself.
    private func buildRing() {
        let sweep: Float = 2.1
        for i in 0..<Self.beads {
            let a = -sweep + 2 * sweep * (Float(i) + 0.5) / Float(Self.beads)
            let r = Self.ringRadius
            let target = beadOfTarget == i
            let bead = root.sphere(target ? 0.0062 : 0.0042, materials.empty,
                                   at: bowlAt + spots.right * (r * sin(a)) + spots.toward * (r * cos(a)) + [0, target ? 0.005 : 0.0035, 0],
                                   scale: target ? [1, 1.4, 1] : [1, 0.8, 1])
            ring.append(bead)
        }
    }

    private var beadOfTarget: Int { min(Self.beads - 1, Int(Double(task.target) / cap * Double(Self.beads))) }

    private func drawRing() {
        let filled = Int((food / cap * Double(Self.beads)).rounded(.down))
        guard filled != shownBeads else { return }
        shownBeads = filled
        let zoneStart = Int(Double(task.target - task.tolerance) / cap * Double(Self.beads))
        for (i, bead) in ring.enumerated() {
            let inZone = i >= zoneStart
            let on = i < filled
            let material = inZone ? (on ? materials.zoneFilled : materials.zone) : (on ? materials.filled : materials.empty)
            bead.model?.materials = [material]
        }
    }

    // MARK: - Dinner

    private func serve() {
        served = 0
        servedPile = pile.count
        let result = GameResult.feed(target: task.target, food: food)
        deck.say(task.check(food: food) == .ready(perfect: true) ? "Exactly \(task.target) g!" : "\(Int(food.rounded())) g: just right", for: 1.5)
        deck.cheer(big: true)
        deck.result = result
    }

    /// The pile goes down over a few seconds.
    private func eat(_ time: Float) {
        served = time
        let left = Int(Float(servedPile) * max(0, 1 - (time - 0.8) / 4))
        while pile.count > left { pile.removeLast().removeFromParent() }
    }

    func tearDown() {
        root.removeFromParent()
        room.walker?.go(to: nil)
    }
}
