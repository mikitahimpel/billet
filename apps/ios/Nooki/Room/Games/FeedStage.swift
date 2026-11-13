import FeatureGames
import GamesInterface
import Pet
import ProfileInterface
import RealityKit
import SwiftUI
import UIKit

/// Fill her bowl, which stands on a kitchen scale: hold anywhere and the bag tips over it; let go and it stops. A ring
/// of beads across the bowl's front fills with the kibble and a green zone on it is the portion her card asks for; the
/// scale's display reads the grams in the bowl. Past the zone the bag keeps pouring, red, up to the cap, and a bowl
/// served that full leaves her stuffed (`FeedPenalty`). Once the bowl is in the zone, Feed serves it and she eats,
/// looking up at the player.
@MainActor
final class FeedStage: GameStage {
    /// One kibble in the air, from `from` into the bowl at `to`.
    private struct Flight {
        let entity: ModelEntity
        let from: SIMD3<Float>
        let to: SIMD3<Float>
        var time: Float
        let length: Float
        /// Bounced out of the bowl onto the mat instead of into it.
        var spills = false
    }

    private static let kibbleTones: [UInt32] = [0x8A5528, 0x9E6530, 0x7A4622, 0xB07A3E]
    private static let bowlHeight: Float = 0.03
    /// The scale's body under the bowl: width, depth and height in metres, its display on the front face.
    private static let scaleSize = SIMD3<Float>(0.21, 0.026, 0.17)
    private static let bowlRadius: Float = 0.05
    private static let floorInside: Float = 0.006
    private static let heapRadius: Float = 0.04
    private static let heapTone = Clay.matte(0x8A5528, roughness: 0.8)
    private static let heapOver = Clay.matte(0xA85A38, roughness: 0.8)
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
    private let pronouns: CatPronouns

    private let bowlAt: SIMD3<Float>
    private let bagRest: SIMD3<Float>
    private let bagPour: SIMD3<Float>
    private let bowl: Entity
    private let bag: Entity
    /// The kibble's mound in the bowl: one shared sphere, squashed, rising with the grams in the bowl.
    private let heap: ModelEntity
    private var shownHeap: Float = 0
    private var heapIsOver = false
    private var shake: Float = 0
    private var clock: Float = 0
    private var ring: [ModelEntity] = []
    private let materials: (empty: PhysicallyBasedMaterial, filled: PhysicallyBasedMaterial, zone: PhysicallyBasedMaterial,
                            zoneFilled: PhysicallyBasedMaterial, over: PhysicallyBasedMaterial,
                            overFilled: PhysicallyBasedMaterial)
    private var shownBeads = -1
    private let readout = Entity()
    private let readoutMaterials = (ok: UnlitMaterial(color: UIColor(hex: 0xC8F7B0)),
                                    over: UnlitMaterial(color: UIColor(hex: 0xFFB59E)))
    private var shownGrams = -1
    private var shownOver = false
    private var pickedUp = false

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
    private var stuffed = false
    private var aftermath: FeedAftermath?
    private var loafed = false
    private var shownHint = ""
    private var mess = FeedMess()
    private var crumbs: [ModelEntity] = []
    /// Seconds into the Clean up button's sweep, while it runs.
    private var assisted: Float?
    private var assistedFrom = 0
    private var messSeen = false
    private var sinceSweep: Float = 0

    /// The most the bowl takes.
    private var cap: Double { Double(task.hardCap) }
    private var zoneEnd: Double { Double(task.target + task.tolerance) }

    /// How far the camera leans toward the bowl while the bag pours.
    var push: Float { tip * 0.6 }

    var seat: SIMD3<Float>? { spots.at(0, -0.13) }

    init(room: CatRoom, deck: GameDeck) {
        self.room = room
        self.deck = deck
        spots = GameSpots(room: room)
        root = room.pivot.group()
        task = FeedTask(full: room.director?.needs?.full ?? 0.5)
        name = CatProfile.name()
        pronouns = CatProfile.pronouns()
        bowlAt = spots.at(0, 0.04, up: Self.scaleSize.y)
        bagRest = spots.at(0.2, -0.05, up: 0.13)
        bagPour = bowlAt + spots.right * 0.045 + [0, 0.115, 0]


        var empty = Clay.matte(0xFFF3E2, roughness: 0.5)
        empty.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        materials = (empty, Clay.matte(0xF2A65E, roughness: 0.4), Clay.matte(0xA9C27E, roughness: 0.5),
                     Clay.matte(0x6F8A4E, roughness: 0.4), Clay.matte(0xE8A08A, roughness: 0.5),
                     Clay.matte(0xC4503A, roughness: 0.4))

        bowl = root.group(at: bowlAt)
        bowl.cylinder(0.006, Self.bowlRadius + 0.004, Clay.matte(0xD8653F, roughness: 0.4), at: [0, 0.003, 0])
        if let mesh = BowlMesh.make(outer: Self.bowlRadius, inner: Self.bowlRadius - 0.005, height: Self.bowlHeight,
                                    floor: Self.floorInside) {
            bowl.addChild(ModelEntity(mesh: mesh, materials: [Clay.matte(0xE98A5B, roughness: 0.4),
                                                              Clay.matte(0x7A4A2A, roughness: 0.9)]))
        }
        heap = bowl.sphere(1, Self.heapTone, at: [0, Self.floorInside, 0], scale: [Self.heapRadius, 0.0005, Self.heapRadius])
        heap.isEnabled = false

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

        buildScale()
        buildRing()
        let seat = spots.at(0, -0.13)
        root.contactBlob(at: spots.at(0, 0.04), width: 0.3, depth: 0.25)
        root.contactBlob(at: bowlAt, width: 0.15, depth: 0.12)
        root.contactBlob(at: spots.at(0.2, -0.05), width: 0.14, depth: 0.1)
        root.contactBlob(at: seat, width: 0.24, depth: 0.16)
        room.send(to: seat, facing: spots.facingPlayer, id: "feed-watch")
        deck.say("Hold to pour \(name)'s \(task.target) g, stop in the green")
        drawRing()
    }

    var focus: [SIMD3<Float>] {
        [bowlAt - spots.right * 0.1, bagRest + spots.right * 0.05 + [0, 0.02, 0], bowlAt + spots.toward * 0.08,
         spots.at(0, -0.13, up: 0.1), spots.at(0, -0.13, up: 0.2)]
    }

    var action: String? { served == nil && canServe ? "Feed" : nil }

    var cue: GameCue? {
        if served == nil, mess.phase == .messy, let crumb = crumbs.first {
            return GameCue(step: 2, gesture: .drag(to: crumb.position + spots.right * 0.07), at: crumb.position - spots.right * 0.04)
        }
        guard served == nil, !canServe, food == 0 else { return nil }
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

    private var isOver: Bool {
        if case .tooMuch = task.check(food: food) { return true }
        return false
    }

    /// In the zone, or past it: past it is served too, and costs.
    private var canServe: Bool { isReady || isOver }

    // MARK: - Touch

    func began(_ touch: GameTouch) {
        guard served == nil else { return }
        if mess.phase == .messy {
            sweep(at: touch)
        } else {
            holding = 0
        }
    }

    func moved(_ touch: GameTouch) {
        if mess.phase == .messy, served == nil { sweep(at: touch) }
    }

    var assist: String? { mess.phase == .messy && served == nil && assisted == nil && holding == nil ? "Clean up" : nil }

    func assistAct() {
        guard mess.phase == .messy, assisted == nil else { return }
        if UIAccessibility.isReduceMotionEnabled {
            sweepAll()
        } else {
            assisted = 0
            assistedFrom = crumbs.count
        }
    }

    /// Kibble under the finger is swept off the mat.
    private func sweep(at touch: GameTouch) {
        var taken = 0
        for index in crumbs.indices.reversed() where touch.distance(to: crumbs[index].position) < 0.03 {
            crumbs.remove(at: index).removeFromParent()
            mess.sweep()
            taken += 1
        }
        if taken > 0, sinceSweep > 0.08 {
            sinceSweep = 0
            deck.stroke()
        }
    }

    private func sweepAll() {
        for crumb in crumbs { crumb.removeFromParent() }
        mess.sweep(crumbs.count)
        crumbs.removeAll()
    }

    private func tidy(_ dt: Float) {
        sinceSweep += dt
        if let t = assisted {
            assisted = t + dt
            let left = Int((Float(assistedFrom) * max(0, 1 - (t + dt) / 0.9)).rounded(.up))
            while crumbs.count > left { crumbs.removeLast().removeFromParent(); mess.sweep() }
            if left == 0 { assisted = nil }
        }
        if mess.phase == .messy, !messSeen {
            messSeen = true
            room.react(toMess: true, seat: spots.at(0, -0.13), back: spots.at(0, -0.19), facing: spots.facingPlayer, id: "feed-watch")
        } else if mess.isSpotless, messSeen, served == nil {
            messSeen = false
            deck.say("Spotless!", for: 1.4)
            deck.cheer()
            room.react(toMess: false, seat: spots.at(0, -0.13), back: spots.at(0, -0.19), facing: spots.facingPlayer, id: "feed-watch")
        }
    }

    func ended(_ touch: GameTouch?) { holding = nil }

    func act() {
        guard served == nil, canServe else { return }
        serve()
    }

    // MARK: - Frame

    func update(_ dt: Float) {
        sinceTap += dt
        if let held = holding { holding = held + dt }
        let pouring = served == nil && !capped && (holding ?? 0) > Self.grace
        tip += ((pouring ? 1 : 0) - tip) * min(1, dt * 7)
        drawBag()
        drawHeap(dt)
        if pouring, tip > 0.85 { pourFlow(dt) }
        fly(dt)
        tidy(dt)
        if let time = served { eat(time + dt, dt: dt) }
        drawRing()
        drawReadout()
        deck.show(min(food / Double(max(task.target, 1)), 1), "Bowl", detail: "\(Int(food.rounded())) / \(task.target) g")
        if served == nil { say(hint) }
    }

    private var hint: String {
        if mess.phase == .messy { return "Sweep up the crumbs, or feed \(name) as it is" }
        if capped { return pronouns.say(.bowlCapped) }
        switch task.check(food: food) {
        case .ready: return "Right there. Let go, tap Feed"
        case .tooLittle(let grams): return food < 1 ? "Hold to pour \(name)'s \(task.target) g, stop in the green" : "\(grams) g to go"
        case .tooMuch: return pronouns.say(.tooMuchWarning)
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
        let rate = (9 + min(held, 2) * 5) * min(1, max((zoneEnd - food) / 9, 0.3))
        debt += rate * Double(dt)
        while debt >= Self.piece, food + Double(flights.count) < cap {
            debt -= Self.piece
            drop()
        }
        let poured = food + Double(flights.count)
        if poured > zoneEnd + 0.5, !pickedUp {
            pickedUp = true
            deck.thump()
        }
        if poured >= cap, !capped {
            capped = true
            debt = 0
            shake = 1
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

    /// The mound's size follows the grams that have landed, eased; past the zone it goes the warning tone, and at the
    /// cap the bowl gives a shudder.
    private func drawHeap(_ dt: Float) {
        clock += dt
        let target = min(Float(pile.count) / Float(max(cap, 1)), 1)
        shownHeap += (target - shownHeap) * min(1, dt * 10)
        heap.isEnabled = shownHeap > 0.01
        heap.scale = [Self.heapRadius * (0.5 + 0.5 * shownHeap), Self.mound(shownHeap), Self.heapRadius * (0.5 + 0.5 * shownHeap)]
        if heapIsOver != isOver {
            heapIsOver = isOver
            heap.model?.materials = [heapIsOver ? Self.heapOver : Self.heapTone]
        }
        if shake > 0 {
            shake = max(0, shake - dt * 3)
            let calm = UIAccessibility.isReduceMotionEnabled
            bowl.position = bowlAt + spots.right * (calm ? 0 : sin(clock * 48) * 0.0015 * shake)
        }
    }

    private static func mound(_ fill: Float) -> Float { 0.003 + 0.02 * fill.squareRoot() }

    private var mouth: SIMD3<Float> { bag.position }

    private func drop() {
        let kibble = root.sphere(0.0062, Clay.matte(Self.kibbleTones.randomElement() ?? 0x8A5528, roughness: 0.75),
                                 at: mouth, scale: [1, 0.65, 1])
        let poured = Int(food) + flights.count + 1
        let spills = FeedMess.spills(poured: poured, zoneEnd: task.target + task.tolerance)
        let inBowl = pile.count + flights.filter { !$0.spills }.count
        flights.append(Flight(entity: kibble, from: mouth + spots.right * Float.random(in: -0.004...0.004),
                              to: spills ? scatter() : slot(inBowl), time: 0, length: Float.random(in: 0.22...0.32),
                              spills: spills))
    }

    private func fly(_ dt: Float) {
        for index in flights.indices.reversed() {
            flights[index].time += dt
            let flight = flights[index]
            let u = min(1, flight.time / flight.length)
            flight.entity.position = simd_mix(flight.from, flight.to, SIMD3(repeating: u * u))
            guard u >= 1 else { continue }
            flights.remove(at: index)
            food += Self.piece
            if flight.spills {
                crumbs.append(flight.entity)
                mess.spill()
                continue
            }
            let local = bowl.convert(position: flight.to, from: root)
            flight.entity.removeFromParent()
            bowl.addChild(flight.entity)
            flight.entity.position = local
            pile.append(flight.entity)
        }
    }

    /// Where a kibble that bounced out lands: round the bowl's foot, on the scale or the mat beyond it.
    private func scatter() -> SIMD3<Float> {
        // Behind and to the sides of the bowl: toward the player the mat lies under the game's own buttons.
        let angle = Float.random(in: 0.85 * .pi...2.15 * .pi)
        let r = Float.random(in: Self.bowlRadius + 0.012...Self.bowlRadius + 0.05)
        let across = r * cos(angle), along = r * sin(angle)
        let onScale = abs(across) < Self.scaleSize.x / 2 - 0.01 && abs(along) < Self.scaleSize.z / 2 - 0.01
        let y = onScale ? bowlAt.y : bowlAt.y - Self.scaleSize.y + 0.0075
        return [bowlAt.x, y, bowlAt.z] + spots.right * across + spots.toward * along
    }

    /// Where the `index`th kibble rests in the bowl, in `root`'s space: spread over the mound it is piling, at the height
    /// the mound will have by then.
    private func slot(_ index: Int) -> SIMD3<Float> {
        let fill = min(Float(index + 1) / Float(max(cap, 1)), 1)
        let reach = Self.heapRadius * (0.5 + 0.5 * fill) * 0.85
        let r = reach * (Float(index) * 0.618).truncatingRemainder(dividingBy: 1).squareRoot()
        let across = r / (Self.heapRadius * (0.5 + 0.5 * fill))
        let height = Self.mound(fill) * (1 - across * across).squareRoot()
        let angle = Float(index) * 2.4
        return bowlAt + [r * cos(angle), Self.floorInside + height, r * sin(angle)]
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
            let bead = root.sphere(target ? 0.0078 : 0.0055, materials.empty,
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
        let zoneStop = Int((zoneEnd / cap * Double(Self.beads)).rounded(.up))
        for (i, bead) in ring.enumerated() {
            let on = i < filled
            let material: PhysicallyBasedMaterial
            if i >= zoneStop {
                material = on ? materials.overFilled : materials.over
            } else if i >= zoneStart {
                material = on ? materials.zoneFilled : materials.zone
            } else {
                material = on ? materials.filled : materials.empty
            }
            bead.model?.materials = [material]
        }
    }

    // MARK: - The scale

    /// A kitchen scale under the bowl: a brushed-steel platform on a slate body with a bezel, a display on its front
    /// face that reads the grams in the bowl in real text, and a foot at each corner.
    private func buildScale() {
        let size = Self.scaleSize
        let body = root.group(at: bowlAt - [0, size.y, 0])
        body.orientation = simd_quatf(from: [0, 0, 1], to: spots.toward)
        body.box(size.x, size.y - 0.006, size.z, r: 0.008, Clay.matte(0x5E6B78, roughness: 0.5), at: [0, (size.y - 0.006) / 2, 0])
        body.box(size.x - 0.012, 0.006, size.z - 0.012, r: 0.004, Clay.matte(0xD6DEE4, roughness: 0.3), at: [0, size.y - 0.003, 0])
        body.box(0.1, 0.0015, 0.1, r: 0.04, Clay.matte(0xC3CDD5, roughness: 0.3), at: [0, size.y + 0.0004, 0])
        let front = size.z / 2 + 0.0008
        body.box(0.108, 0.02, 0.003, r: 0.004, Clay.matte(0x2B323A, roughness: 0.4), at: [0, size.y / 2 - 0.002, front])
        readout.position = [0, size.y / 2 - 0.0035, front + 0.0018]
        body.addChild(readout)
        let text = ModelEntity(mesh: .generateBox(size: 0.0001), materials: [readoutMaterials.ok])
        readout.addChild(text)
        for x: Float in [-1, 1] {
            for z: Float in [-1, 1] {
                body.cylinder(0.004, 0.007, Clay.matte(0x2B323A, roughness: 0.8), at: [x * (size.x / 2 - 0.016), 0.002, z * (size.z / 2 - 0.016)])
            }
        }
    }

    /// The display's digits: re-set only when the grams (or the zone's colour) change, since each is a new mesh.
    private func drawReadout() {
        let grams = Int(food.rounded())
        let over = isOver
        guard grams != shownGrams || over != shownOver, let text = readout.children.first as? ModelEntity else { return }
        shownGrams = grams
        shownOver = over
        let mesh = MeshResource.generateText(
            "\(grams) g", extrusionDepth: 0.0003, font: .monospacedSystemFont(ofSize: 0.013, weight: .bold),
            containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        text.model = ModelComponent(mesh: mesh, materials: [over ? readoutMaterials.over : readoutMaterials.ok])
        let bounds = mesh.bounds
        text.position = [-bounds.center.x, -bounds.center.y, 0]
    }

    // MARK: - Dinner

    private func serve() {
        served = 0
        servedPile = pile.count
        assisted = nil
        let result = GameResult.feed(target: task.target, food: food, crumbs: mess.pieces, spotless: mess.isSpotless)
        if result.tooMuch {
            deck.say(result.messy ? "Too much, and crumbs everywhere" : "Too much! \(name) is stuffed", for: 1.8)
            deck.thump()
        } else {
            deck.say(task.check(food: food) == .ready(perfect: true) ? "Exactly \(task.target) g!" : "\(Int(food.rounded())) g: just right", for: 1.5)
            deck.cheer(big: true)
        }
        stuffed = result.tooMuch
        aftermath = FeedAftermath(stuffed: result.tooMuch)
        deck.result = result
    }

    /// The pile goes down over a few seconds.
    private func eat(_ time: Float, dt: Float) {
        served = time
        let left = Int(Float(servedPile) * max(0, 1 - (time - 0.8) / (stuffed ? 6 : 4)))
        while pile.count > left { pile.removeLast().removeFromParent() }
        guard let acts = aftermath?.advance(Double(dt)) else { return }
        for act in acts {
            switch act {
            case .loaf:
                loafed = true
                room.walker?.settle(.loaf)
            case .yawn: room.walker?.behavior.perform(.yawn)
            case .slowBlink: room.walker?.behavior.perform(.slowBlink)
            }
        }
    }

    func tearDown() {
        root.removeFromParent()
        if loafed { room.walker?.settle(.sit) }
        room.walker?.go(to: nil)
    }
}
