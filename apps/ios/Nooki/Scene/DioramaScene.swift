import DecorInterface
import Pet
import RealityKit
import SwiftUI
import UIKit

private enum Tone {
    static let wood: UInt32 = 0xB46C3C
    static let woodDark: UInt32 = 0x8C4F2B
    static let woodLight: UInt32 = 0xCF8E58
    static let wall: UInt32 = 0xF6E4C8
    static let snow: UInt32 = 0xFFFBF5
    static let blanket: UInt32 = 0xE98A5B
    static let plush: UInt32 = 0xFBF1E3
    static let plushShade: UInt32 = 0xEADBC6
    static let rug: UInt32 = 0xDDB98A
    static let rugEdge: UInt32 = 0xC39A69
    static let leaf: UInt32 = 0x93A86A
    static let leafDark: UInt32 = 0x6F8A4E
    static let pot: UInt32 = 0xC7744A
    static let ink: UInt32 = 0x5B3A28
    static let windowGlow: UInt32 = 0xFFE0A0
    static let bulb: UInt32 = 0xFFD27A
    static let flame: UInt32 = 0xFFB347
}

/// A cozy isometric room: walls, floor and lights drawn here, the furniture modelled in Blender (Tools/make_room.py,
/// Room_*.usdz) in the room's own coordinates.
/// Coordinates are meters; the floor's top surface sits at y = 0, the room spans x, z in -0.5...0.5.
final class DioramaScene: CatRoom {
    private var flame = Entity()
    private var candleLight = Entity()
    private var bulbs: [Entity] = []
    /// Invisible hit boxes over the things a tap or double tap sends Mochi to.
    private let tree = Entity()
    private let sill = Entity()
    private let bed = Entity()
    private let ball = Entity()
    private let basket = Entity()
    /// The toys she plays with, moved when they bounce; filled once their models load.
    private var toyBall = Entity()
    private var yarn = Entity()
    private var ballVisit: CatWalker.Destination?
    private var basketVisit: CatWalker.Destination?
    private var sillVisit: CatWalker.Destination?
    /// Toys bouncing under her paws: each one's resting position, when the bounce started and whether it rolls.
    private var bounces: [(toy: Entity, at: SIMD3<Float>, start: Float, spins: Bool)] = []

    private let wallHeight: Float = 0.8

    /// The furniture and Mochi are both in: the room looks finished, so the launch splash can lift.
    var isReady: Bool { furnished && baseFurnished && walker != nil }
    private var furnished = false
    /// Set by the stage once every piece of the room's own furniture that stands has its model.
    var baseFurnished = false
    private var layout = DecorLayout()
    private var treeVisit: CatWalker.Destination?
    private var lampLight = Entity()
    private var catHomeFrame: (position: SIMD3<Float>, yaw: Float)?

    override init() {
        super.init()
        useBakedShell(named: "Room_shell")
        buildFloor()
        buildWalls()
        setPolaroids([])
        addContactShadow(named: "room_contact", x0: -0.595, z0: -0.595, x1: 0.56, z1: 0.56, y: 0.017)
        buildFairyLights()
        buildHitBoxes()
        buildCat()
        buildCandle()
        buildVisits()
        buildMotes()
        buildLighting()
        loadFurniture()
    }

    private var flameClock = Throttle(interval: PulseRates.active.flame)
    private var candleClock = Throttle(interval: PulseRates.active.candle)
    private var bulbClock = Throttle(interval: PulseRates.active.bulbs)

    override func tick(_ dt: Float) {
        super.tick(dt)
        let t = time

        if swaying {
            let rates = PulseRates.at(active: isActive, slowedBy: pulseSlowdown)
            flameClock.interval = rates.flame
            candleClock.interval = rates.candle
            bulbClock.interval = rates.bulbs
            let flicker = 1 + 0.12 * sin(t * 13) + 0.08 * sin(t * 7.3 + 1)
            if flameClock.fires(dt) {
                flame.scale = Self.flameRadius * [0.85, 1.45 * flicker, 0.85]
                SceneWrites.note(.flameScale)
            }
            if candleClock.fires(dt), var light = candleLight.components[PointLightComponent.self] {
                light.intensity = 450 * flicker
                candleLight.components.set(light)
                SceneWrites.note(.candleLight)
            }
            // A bulb's pulse takes seconds; four to ten steps a second read as continuous.
            if bulbClock.fires(dt) {
                for (i, bulb) in bulbs.enumerated() {
                    let s = 1 + 0.22 * sin(t * 2.1 + Float(i) * 1.3)
                    bulb.scale = .init(repeating: Self.bulbRadius * s)
                }
                SceneWrites.note(.bulbScale, bulbs.count)
            }
        }

        // Toys hop with each of her two pats, the ball rolling a little, then settle.
        bounces.removeAll { t - $0.start > 1.4 }
        for bounce in bounces {
            let u = t - bounce.start
            let fade = 1 - u / 1.4
            bounce.toy.position = bounce.at + [0, (bounce.spins ? 0.018 : 0.008) * abs(sin(u * .pi / 0.46)) * fade, 0]
            if bounce.spins { bounce.toy.orientation = .y(u * 3) * .x(sin(u * 9) * 0.3 * fade) }
        }
    }

    // MARK: - Taps

    override func tapped(_ entity: Entity) {
        guard !isShowcasing else { return }
        if entity === ball, !cutOff.contains(.ball) { send(to: ballVisit) }
        if entity === basket, !cutOff.contains(.basket) { send(to: basketVisit) }
    }

    override func doubleTapped(_ entity: Entity) {
        if let photo = entity.children.first(where: { $0.name == Self.photoName }) { return focus(on: photo) }
        guard !isShowcasing, let walker else { return }
        if entity === tree, let treeVisit, !cutOff.contains(.tree) { send(to: treeVisit) }
        if entity === sill, !cutOff.contains(.sill) { send(to: sillVisit) }
        if entity === bed { send(to: nil) }
    }

    /// Sends her off; she stays there a while before her brain takes her on.
    private func send(to destination: CatWalker.Destination?) {
        guard let walker else { return }
        walker.go(to: destination)
        let spot = destination.flatMap { d in catSpots.first { $0.value.id == d.id }?.key } ?? .home
        director?.sent(to: spot)
    }

    /// Visits a piece the player stood in the room has cut off; she does not go there.
    var cutOff: Set<NookiSpot> = []

    /// Places she can use at the pieces the player stood in the room.
    var placedSpots: [NookiSpot: CatWalker.Destination] = [:] {
        didSet { director?.update(spots: catSpots) }
    }

    override var catSpots: [NookiSpot: CatWalker.Destination] {
        var spots: [NookiSpot: CatWalker.Destination] = [:]
        spots[.tree] = treeVisit
        if !cutOff.contains(.sill) { spots[.sill] = sillVisit }
        if !cutOff.contains(.ball) { spots[.ball] = ballVisit }
        if !cutOff.contains(.basket) { spots[.basket] = basketVisit }
        spots.merge(placedSpots) { current, _ in current }
        return spots
    }

    override var catKeepOut: (center: SIMD2<Float>, radius: Float)? { (SIMD2(bedCenter.x, bedCenter.z), 0.22) }

    override func catBuilt() {
        arrange(layout)
        // `-uitestSend tree|sill|ball|basket|home` sends her there a few seconds after she is built, for UI tests
        // that cannot tap the room.
        guard let target = UserDefaults.standard.string(forKey: "uitestSend") else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            switch target {
            case "tree": if let treeVisit { send(to: treeVisit) }
            case "sill": if let sillVisit { send(to: sillVisit) }
            case "ball": if let ballVisit { send(to: ballVisit) }
            case "basket": if let basketVisit { send(to: basketVisit) }
            default: send(to: nil)
            }
        }
    }

    private func bounce(_ toy: Entity, spins: Bool) {
        guard !bounces.contains(where: { $0.toy === toy }) else { return }
        bounces.append((toy, toy.position, time, spins))
    }

    // MARK: - Structure

    private func buildFloor() {
        pivot.box(1.14, 0.1, 1.14, r: 0.03, Clay.matte(Tone.woodDark), at: [-0.01, -0.05, -0.01])
        for i in 0..<7 {
            let z = -0.45 + Float(i) * 0.15
            let tone = i.isMultiple(of: 2) ? Tone.wood : Tone.woodLight
            pivot.box(1.04, 0.014, 0.146, r: 0.005, Clay.matte(tone, roughness: 0.7), at: [0.0, 0.007, z])
        }
    }

    private func buildWalls() {
        let h = wallHeight
        let wall = Clay.matte(Tone.wall, roughness: 0.95)
        let wood = Clay.matte(Tone.wood)
        let snow = Clay.matte(Tone.snow, roughness: 0.6)

        pivot.box(0.05, h, 1.06, r: 0.01, wall, at: [-0.525, h / 2, -0.03])
        pivot.box(1.06, h, 0.05, r: 0.01, wall, at: [-0.03, h / 2, -0.525])

        // Baseboards.
        pivot.box(0.014, 0.05, 1.0, r: 0.004, wood, at: [-0.493, 0.025, 0])
        pivot.box(1.0, 0.05, 0.014, r: 0.004, wood, at: [0, 0.025, -0.493])

        // Corner posts and top beams.
        for (x, z) in [(-0.535, 0.52), (-0.535, -0.535), (0.52, -0.535)] as [(Float, Float)] {
            pivot.box(0.075, h + 0.06, 0.075, r: 0.012, wood, at: [x, (h + 0.06) / 2, z])
        }
        pivot.box(0.085, 0.065, 1.13, r: 0.015, wood, at: [-0.535, h + 0.02, -0.01])
        pivot.box(1.13, 0.065, 0.085, r: 0.015, wood, at: [-0.01, h + 0.02, -0.535])

        // Snow resting on the beams.
        pivot.box(0.12, 0.05, 0.42, r: 0.024, snow, at: [-0.535, h + 0.07, 0.22])
        pivot.box(0.11, 0.04, 0.3, r: 0.019, snow, at: [-0.535, h + 0.065, -0.28])
        pivot.sphere(0.04, snow, at: [-0.535, h + 0.075, 0.0], scale: [1.2, 0.8, 1.4])
        pivot.box(0.44, 0.05, 0.12, r: 0.024, snow, at: [0.24, h + 0.07, -0.535])
        pivot.box(0.26, 0.04, 0.11, r: 0.019, snow, at: [-0.3, h + 0.065, -0.535])
        pivot.sphere(0.045, snow, at: [-0.535, h + 0.08, -0.535], scale: [1.3, 0.9, 1.3])
    }

    // MARK: - Polaroids

    /// Twine garland on the back wall, left of the shelf; each pinned moment hangs from it as a small polaroid.
    private let garland: Entity = {
        let garland = Entity()
        garland.components.set(ShellLive())
        return garland
    }()
    private static let garlandSlots = 6
    private static let garlandEnds: (x0: Float, x1: Float, y: Float, sag: Float) = (-0.46, -0.1, 0.64, 0.035)

    private static func garlandPoint(_ t: Float) -> SIMD3<Float> {
        let e = garlandEnds
        return [e.x0 + (e.x1 - e.x0) * t, e.y - e.sag * sin(t * .pi), -0.492]
    }

    private static let photoName = "photo"

    /// One polaroid per image, the rest of the slots as blank frames.
    func setPolaroids(_ images: [UIImage]) {
        garland.children.removeAll()
        if garland.parent == nil { pivot.addChild(garland) }

        // Twine as short straight segments following the sag.
        let twine = Clay.matte(0xB89A78, roughness: 1)
        let steps = 12
        for i in 0..<steps {
            let a = Self.garlandPoint(Float(i) / Float(steps)), b = Self.garlandPoint(Float(i + 1) / Float(steps))
            let d = b - a
            garland.box(simd_length(d) + 0.002, 0.003, 0.003, r: 0, twine, at: (a + b) / 2, rotation: .z(atan2(d.y, d.x)))
        }

        let frame = Clay.matte(0xFFFBF3, roughness: 0.7)
        let blank = Clay.matte(0xE9D6BC, roughness: 0.9)
        let clip = Clay.matte(Tone.woodLight)
        for slot in 0..<Self.garlandSlots {
            let t = (Float(slot) + 0.5) / Float(Self.garlandSlots)
            let top = Self.garlandPoint(t)
            // Alternating tilt so the row looks hand-hung.
            let tilt: Float = [0.07, -0.05, 0.04, -0.08, 0.06, -0.03][slot]
            let card = garland.group(at: top + [0, -0.004, 0], rotation: .z(tilt))
            card.box(0.066, 0.08, 0.004, r: 0.002, frame, at: [0, -0.04, 0.002])
            card.box(0.012, 0.018, 0.008, r: 0.002, clip, at: [0, 0, 0.004])

            let photoAt: SIMD3<Float> = [0, -0.033, 0.0045]
            if slot < images.count, let photo = Self.photoMaterial(images[slot]) {
                card.model(.generatePlane(width: 0.056, height: 0.056), photo, at: photoAt).name = Self.photoName
                Self.tappable(card, size: [0.07, 0.086, 0.012], at: [0, -0.04, 0.004])
            } else {
                card.box(0.056, 0.056, 0.001, r: 0, blank, at: photoAt)
            }
        }
        // Rebuilt after buildLighting handed out the receiver, so the new cards need it too.
        if let iblReceiver { garland.forEachDescendant { $0.components.set(iblReceiver) } }
    }

    /// Square center crop at polaroid resolution, so the wall never holds full-size photos in memory.
    private static func photoMaterial(_ image: UIImage) -> PhysicallyBasedMaterial? {
        let side: CGFloat = 256
        let crop = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let s = side / crop
            image.draw(in: CGRect(x: (crop - image.size.width) / 2 * s, y: (crop - image.size.height) / 2 * s,
                                  width: image.size.width * s, height: image.size.height * s))
        }
        guard let cg = square.cgImage,
              let texture = try? TextureResource(image: cg, options: .init(semantic: .color)) else { return nil }
        var m = Clay.matte(0xFFFFFF, roughness: 0.55)
        m.baseColor = .init(tint: .white, texture: .init(texture))
        return m
    }

    /// Spheres carry their radius in their scale, so the per-frame pulse and flicker multiply it back in.
    private static let bulbRadius: Float = 0.011
    private static let flameRadius: Float = 0.011

    private func buildFairyLights() {
        let material = Clay.glow(Tone.bulb, intensity: 2.5)
        let top = wallHeight - 0.05
        let count = 13
        for i in 0..<count {
            let t = Float(i) / Float(count - 1)
            let sag = 0.05 * abs(sin(t * .pi * 2))
            bulbs.append(pivot.sphere(Self.bulbRadius, material, at: [-0.47 + t * 0.94, top - sag, -0.47]))
            bulbs.append(pivot.sphere(Self.bulbRadius, material, at: [-0.47, top - sag, -0.47 + t * 0.94]))
        }
    }

    // MARK: - Furniture

    /// Center of the donut bed on the floor.
    private let bedCenter: SIMD3<Float> = [0.06, 0.014, -0.04]
    /// Mochi sits about as tall as the nightstand, on the bed's cushion; Mochi.ply itself is 0.26 m tall.
    private let catScale: Float = 0.68

    /// The furniture and the two toys, loaded in the background side by side and lit like the rest of the room.
    private func loadFurniture() {
        let pieces = [("Room_furniture", pivot), ("Room_ball", ball), ("Room_yarn", basket)]
        let loads = pieces.map { name, _ in Task { try await Entity(named: name, in: .main) } }
        Task { [weak self] in
            for ((name, parent), load) in zip(pieces, loads) {
                let model: Entity
                do {
                    model = try await load.value
                } catch {
                    print("\(name) failed to load: \(error)")
                    continue
                }
                guard let self else { return }
                model.forEachDescendant { entity in
                    if let iblReceiver { entity.components.set(iblReceiver) }
                    entity.components.set(GroundingShadowComponent(castsShadow: true))
                    if let glow = RoomPieces.glows[entity.name], var mesh = entity.components[ModelComponent.self] {
                        mesh.materials = mesh.materials.map { _ in Clay.glow(glow.tone, intensity: glow.intensity) }
                        entity.components.set(mesh)
                    }
                }
                parent.addChild(model)
                if name == "Room_ball" { toyBall = model }
                if name == "Room_yarn" { yarn = model }
            }
            self?.furnished = true
        }
    }

    /// Where taps land: the cat tree, the sill, the bed, the ball on the rug and the yarn basket.
    private func buildHitBoxes() {
        for (entity, at, size, center) in [
            (tree, SIMD3<Float>(0.36, 0.014, -0.36), SIMD3<Float>(0.2, 0.4, 0.2), SIMD3<Float>(0, 0.2, 0)),
            (sill, [-0.41, 0.262, 0], [0.2, 0.3, 0.44], [0, 0.14, 0]),
            (bed, bedCenter, [0.36, 0.14, 0.36], [0, 0.07, 0]),
            (ball, [-0.19, 0.047, 0.325], [0.1, 0.1, 0.1], .zero),
            (basket, [0.37, 0.014, 0.36], [0.18, 0.14, 0.18], [0, 0.07, 0]),
        ] {
            entity.position = at
            pivot.addChild(entity)
            Self.tappable(entity, size: size, at: center)
        }
    }

    /// Mochi on the bed cushion; she can hop out onto the rug, cross it and leap up to the top of the cat tree.
    private func buildCat() {
        let rest: Float = 0.75 + .pi
        // Where the standing splat's origin goes for the seated one to sit on the cushion, `mount` behind it.
        let mount: SIMD3<Float> = [0.01, 0, -0.058]
        let bed = bedCenter + [0, 0.05, 0.01] - simd_quatf.y(rest).act(mount * catScale)
        buildCat(at: bed, rests: [rest, rest], route: [
            .init(at: [0.36, 0.396, -0.36]),
            .init(at: [0.3, 0.023, -0.12], move: .jump),
            .init(at: [0.2, 0.023, 0.2], move: .walk),
            .init(at: bed, move: .jump),
        ], scale: catScale, wandering: false)
    }

    /// The nightstand candle's flickering flame and its own little light; the candle itself is in the furniture.
    private func buildCandle() {
        flame = pivot.sphere(Self.flameRadius, Clay.glow(Tone.flame, intensity: 8), at: [-0.41, 0.287, 0.38],
                             scale: [0.85, 1.45, 0.85])
        candleLight = pivot.group(at: [-0.37, 0.33, 0.38])
        var light = PointLightComponent(color: UIColor(hex: 0xFFAA55), intensity: 450, attenuationRadius: 0.6)
        light.attenuationFalloffExponent = 2
        candleLight.components.set(light)

        // The stool lamp's light.
        lampLight = pivot.group(at: Self.lampLightHome)
        lampLight.components.set(PointLightComponent(color: UIColor(hex: 0xFFC27A), intensity: 700, attenuationRadius: 0.7))
    }

    /// Where a tap or double tap sends her from the bed, each path starting where she sits in it.
    private func buildVisits() {
        // Pounce: out of the bed, then a short leap onto the ball's spot; it bounces under her pats.
        let pounceFrom: SIMD3<Float> = [0.0, 0.023, 0.19], pounceTo: SIMD3<Float> = [-0.1, 0.023, 0.26]
        ballVisit = .init(id: "ball", path: [.init(at: pounceFrom, move: .jump), .init(at: pounceTo, move: .jump)],
                          rest: atan2(-(pounceTo.x - pounceFrom.x), -(pounceTo.z - pounceFrom.z)), play: true,
                          arrive: { [unowned self] in bounce(toyBall, spins: true) })
        basketVisit = .init(id: "basket", path: [.init(at: [0.16, 0.023, 0.16], move: .jump), .init(at: [0.27, 0.014, 0.26])],
                            rest: atan2(-1, -1), play: true, arrive: { [unowned self] in bounce(yarn, spins: false) })
        sillVisit = .init(id: "sill", path: [
            .init(at: [-0.12, 0.023, 0.1], move: .jump),
            .init(at: [-0.24, 0.023, 0.04]),
            .init(at: [-0.38, 0.295, 0.01], move: .jump),
        ], rest: 0.75 + .pi)
    }

    // MARK: - Arranging

    private static let treeHome: SIMD3<Float> = [0.36, 0.014, -0.36]
    private static let sillHome: SIMD3<Float> = [-0.41, 0.262, 0]
    private static let ballHome: SIMD3<Float> = [-0.19, 0.047, 0.325]
    private static let basketHome: SIMD3<Float> = [0.37, 0.014, 0.36]
    private static let flameHome: SIMD3<Float> = [-0.41, 0.287, 0.38]
    private static let candleLightHome: SIMD3<Float> = [-0.37, 0.33, 0.38]
    private static let lampLightHome: SIMD3<Float> = [-0.15, 0.314, -0.34]
    private static let restYaw: Float = 0.75 + .pi

    /// Brings what belongs to the room's own pieces (the hit boxes, the candle and the lamp light, the toys, and
    /// every place she goes) to where the player stood them. Cheap when nothing moved.
    func arrange(_ next: DecorLayout) {
        layout = next
        func place(_ entity: Entity, _ id: String, _ home: SIMD3<Float>) {
            guard let frame = PieceFrame(id, in: next) else {
                entity.isEnabled = false
                return
            }
            entity.isEnabled = true
            entity.position = frame.map(home)
            entity.orientation = frame.orientation
        }
        place(tree, "base-cattree", Self.treeHome)
        place(sill, "base-windowseat", Self.sillHome)
        place(ball, "base-rug", Self.ballHome)
        place(basket, "base-basket", Self.basketHome)
        place(flame, "base-nightstand", Self.flameHome)
        place(candleLight, "base-nightstand", Self.candleLightHome)
        place(lampLight, "base-lamp", Self.lampLightHome)
        flame.orientation = .identity

        let spawn = next.spawnSpot()
        let floor: Float = 0.023
        let from: SIMD3<Float> = [Float(spawn.x), floor, Float(spawn.z)]

        /// A floor stop she can stand on: where a piece the player moved stands on it, the free floor beside it, so she
        /// walks to the piece and never into it. Nil when no floor is near.
        func standing(_ point: SIMD3<Float>, beside piece: String) -> SIMD3<Float>? {
            next.standing(near: (Double(point.x), Double(point.z)), beside: piece)
                .map { [Float($0.x), point.y, Float($0.z)] }
        }

        func walk(to id: String, _ home: SIMD3<Float>, yaw extra: Float = 0) -> (SIMD3<Float>, Float)? {
            guard let frame = PieceFrame(id, in: next) else { return nil }
            guard let point = standing(frame.map(home), beside: id) else { return nil }
            return (point, atan2(-(point.x - from.x), -(point.z - from.z)))
        }

        if let (to, rest) = walk(to: "base-rug", [-0.1, floor, 0.26]) {
            ballVisit = .init(
                id: "ball", path: [.init(at: from, move: .jump), .init(at: to, move: .jump)], rest: rest, play: true,
                arrive: { [unowned self] in bounce(toyBall, spins: true) })
        }
        if let (to, _) = walk(to: "base-basket", [0.27, 0.014, 0.26]) {
            basketVisit = .init(
                id: "basket", path: [.init(at: from, move: .jump), .init(at: to)], rest: atan2(-1, -1), play: true,
                arrive: { [unowned self] in bounce(yarn, spins: false) })
        }
        if let seat = PieceFrame("base-windowseat", in: next), let stop = standing(seat.map([-0.24, floor, 0.04]), beside: "base-windowseat") {
            sillVisit = .init(
                id: "sill",
                path: [
                    .init(at: from, move: .jump), .init(at: stop),
                    .init(at: seat.map([-0.38, 0.295, 0.01]), move: .jump),
                ], rest: Self.restYaw + seat.yaw)
        }

        if let tree = PieceFrame("base-cattree", in: next), let approach = next.anchors().first {
            let top = tree.map([0.36, 0.396, -0.36])
            treeVisit = .init(
                id: "main",
                path: [
                    .init(at: from, move: .jump), .init(at: [Float(approach.x), floor, Float(approach.z)]),
                    .init(at: top, move: .jump),
                ], rest: Self.restYaw)
        } else {
            treeVisit = nil
        }

        if let home = next.catHome() {
            let seatPoint: SIMD3<Float>
            let yaw: Float
            if let bed = PieceFrame("base-donutbed", in: next), home.item == "base-donutbed" {
                seatPoint = bed.map(bedCenter + [0, 0.05, 0.01])
                yaw = Self.restYaw + bed.yaw
            } else {
                seatPoint = [Float(home.seat.x), 0.014 + Float(home.height) + 0.05, Float(home.seat.z)]
                yaw = Self.restYaw + Float(home.placement.angle)
            }
            // Where the standing splat's origin goes for the seated one to sit on the cushion, `mount` behind it.
            let mount: SIMD3<Float> = [0.01, 0, -0.058]
            let origin = seatPoint - simd_quatf.y(yaw).act(mount * catScale)
            bed.isEnabled = true
            bed.position = [seatPoint.x, 0.014, seatPoint.z]
            walker?.rehome(at: origin, yaw: yaw, main: treeVisit)
        } else {
            bed.isEnabled = false
        }
        director?.update(spots: catSpots)
    }

    private func buildLighting() {
        // Warm ambient from a generated two-tone environment, baked in the background.
        if let image = Self.gradientImage(top: Daylight.rgb(0xFFE7C4), bottom: Daylight.rgb(0xB97A45)) {
            Task {
                guard let env = try? await EnvironmentResource(equirectangular: image) else { return }
                let ibl = Entity()
                ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.4))
                receiveAmbient(from: ibl)
            }
        }

        let sun = Entity()
        var dir = DirectionalLightComponent(color: UIColor(hex: 0xFFE2BC), intensity: 800)
        dir.isRealWorldProxy = false
        sun.components.set(dir)
        Self.castShadow(sun)
        sun.look(at: [0, 0, 0], from: [1.4, 2.2, 0.9], relativeTo: nil)
        root.addChild(sun)

        // Light pouring in through the window.
        let window = pivot.group(at: [-0.3, 0.47, 0.02])
        window.components.set(PointLightComponent(color: UIColor(hex: 0xFFB866), intensity: 1800, attenuationRadius: 1.1))

        addBloom()
    }
}
