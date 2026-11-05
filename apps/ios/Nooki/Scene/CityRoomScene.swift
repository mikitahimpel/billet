import RealityKit
import UIKit

private enum Tone {
    static let wall: UInt32 = 0xECD9C0
    static let floor: UInt32 = 0x9C6C4C
    static let floorLight: UInt32 = 0xA97A58
    static let wood: UInt32 = 0x8A5A3C
    static let bedFrame: UInt32 = 0xE8D2B2
    static let mattress: UInt32 = 0xFBF0DE
    static let blanket: UInt32 = 0xF0663A
    static let pillow: UInt32 = 0xF4E2C8
    static let crate: UInt32 = 0xD8653F
    static let shade: UInt32 = 0xF7ECD8
    static let rug: UInt32 = 0xDCCAB4
    static let rugEdge: UInt32 = 0xC6B099
    static let leaf: UInt32 = 0x93A86A
    static let leafDark: UInt32 = 0x6F8A4E
    static let pot: UInt32 = 0xE9D9B8
    static let bulb: UInt32 = 0xFFD27A
    static let paper: UInt32 = 0xF6EFE2
    static let heart: UInt32 = 0xE0554A
    static let frame: UInt32 = 0xF5EAD8
}

/// The second room, ported from nooki-scene/src/three/cityRoom.js: a bedroom with a wide window onto a living town,
/// lit by the time of day (the real local hour), where Mochi wanders between her bed and the windowsill.
/// The window looks out on one of the suburb views, painted for the hour in layers at their own depths with its life
/// moving (see WindowPane). Ilya's TownPicture stays as the fallback when a view can't be painted.
final class CityRoomScene: CatRoom {
    private enum Clock {
        case live
        /// A whole day in `seconds`.
        case cycle(seconds: Float)
    }

    private let wallHeight: Float = 0.8
    // The window in the back wall (z = -0.525), in room units.
    private let opening: (left: Float, right: Float, bottom: Float, top: Float) = (-0.4, 0.4, 0.28, 0.72)
    private var windowCenter: SIMD3<Float> { [0, (opening.bottom + opening.top) / 2, -0.525] }
    private var sillTop: Float { opening.bottom + 0.0125 }
    private let catBed: (at: SIMD3<Float>, scale: Float) = ([0.28, 0.014, 0.27], 0.6)
    /// cat-standing.ply is 0.26 m tall on all fours; here Mochi sits about as tall as the nightstand.
    private let catScale: Float = 0.5 * (0.162 / 0.152)

    /// The view behind the glass, repainted as the light changes and the view's life moves.
    private var pane: WindowPane?
    /// True once a suburb view has been shown; the town is painted only before that, or if one can't be.
    private var showsView = false
    private var townHour: Float = -1
    private var townAge: Float = 0
    private var painting = false
    private var clock = Clock.live
    private var hour = Daylight.localHour()
    private var light = Daylight.sample(Daylight.localHour())
    private var lightHour: Float = -1
    /// The hour and lamp brightness the room's lights and glowing materials were last set for.
    private var appliedHour: Float = -1
    private var appliedLamps: Float = -1
    private var environment: EnvironmentResource?

    private let sun = Entity()
    private let fill = Entity()
    private var skyLight = Entity()
    private var lampLight = Entity()
    private var fairyLight = Entity()
    private var candleLight = Entity()
    private var lampShade: ModelEntity?
    private var bulbs: [ModelEntity] = []
    private var setClock: (Float) -> Void = { _ in }
    private let ibl = Entity()

    override init() {
        super.init()
        buildFloor()
        buildWalls()
        buildWindow()
        buildFairyLights()
        buildRug()
        buildBed()
        buildNightstand()
        buildSillProps()
        buildDecor()
        let bedSeat = catBed.at + [0, 0.072 * catBed.scale, 0]
        buildCat(at: [0.25, sillTop, -0.44], rests: [.pi + 0.75, .pi + 0.55], route: [
            .init(at: bedSeat),
            .init(at: [0.13, 0.014, 0.13], move: .jump),
            .init(at: [0.16, 0.014, -0.07], move: .walk),
            .init(at: [0.15, 0.204, -0.27], move: .jump),
            .init(at: [0.25, sillTop, -0.44], move: .jump),
        ], scale: catScale, wandering: true)
        buildMotes()
        buildLighting()
        applyLight()
    }

    override var roomShowcase: [ShowcaseStep] {
        [.init(label: "Day and night", seconds: 14, start: { [unowned self] in clock = .cycle(seconds: 14) },
               end: { [unowned self] in clock = .live })]
    }

    // MARK: - Time

    override func tick(_ dt: Float) {
        super.tick(dt)
        switch clock {
        case .live: hour = Daylight.localHour()
        case .cycle(let seconds): hour = (hour + dt * 24 / seconds).truncatingRemainder(dividingBy: 24)
        }
        light = Daylight.sample(hour)
        paintTown(dt)
        setClock(hour)
        // The room's lights change slowly; they are redone once the hour has moved on a little.
        let moved = abs(hour - appliedHour)
        if min(moved, 24 - moved) > 0.1 { applyLight() }
    }

    private func applyLight() {
        appliedHour = hour
        let darkness = light.darkness
        var sunLight = DirectionalLightComponent(color: Daylight.color(light.sun), intensity: 320 * light.lightIntensity)
        sunLight.isRealWorldProxy = false
        sun.components.set(sunLight)
        sun.look(at: .zero, from: light.lightDirection * 3, relativeTo: pivot)

        let fillColor = simd_mix(light.horizon, light.top, SIMD3(repeating: 0.4))
        fill.components.set(DirectionalLightComponent(color: Daylight.color(fillColor), intensity: 300 * (0.25 + 0.5 * (1 - darkness))))
        setPoint(skyLight, color: light.horizon, lumens: 2500 * (1 - darkness * 0.85), radius: 1.2)

        // People switch the lamps on as it gets dark.
        let lamps = smoothstep(darkness, 0.2, 0.7)
        setPoint(lampLight, color: Daylight.rgb(0xFFC27A), lumens: 2200 * lamps, radius: 1.1)
        setPoint(fairyLight, color: Daylight.rgb(0xFFC27A), lumens: 900 * lamps, radius: 1)
        setPoint(candleLight, color: Daylight.rgb(0xFFAA55), lumens: 500 * (0.3 + 0.7 * lamps), radius: 0.5)
        // New materials are costly, so the glowing bits are only redone as the lamps brighten or dim.
        if abs(lamps - appliedLamps) > 0.02 {
            appliedLamps = lamps
            lampShade?.model?.materials = [Clay.glow(Tone.shade, intensity: 0.2 + 2.6 * lamps)]
            let bulb = Clay.glow(Tone.bulb, intensity: 0.4 + 4 * lamps)
            for b in bulbs { b.model?.materials = [bulb] }
        }

        // The ambient light follows the sky. Baking it is heavy, so it is rebaked only as the real hour moves on, never
        // while the day is cycling; its brightness follows every time.
        if case .live = clock, abs(light.hour - lightHour) > 0.1 {
            lightHour = light.hour
            // Kept warm like the other room's, only tinted by the sky.
            let top = simd_mix(Daylight.rgb(0xFFE7C4), light.top, SIMD3(repeating: 0.3))
            let bottom = simd_mix(Daylight.rgb(0xB97A45), light.horizon, SIMD3(repeating: 0.25))
            if let image = Self.gradientImage(top: top, bottom: bottom) {
                Task { [weak self] in
                    guard let env = try? await EnvironmentResource(equirectangular: image), let self else { return }
                    environment = env
                    applyAmbient()
                }
            }
        }
        applyAmbient()
    }

    private func applyAmbient() {
        guard let environment else { return }
        ibl.components.set(ImageBasedLightComponent(source: .single(environment),
                                                    intensityExponent: log2(max(light.env, 0.05) / 0.85) - 0.4))
    }

    /// Shows the next frame of the window's view, a few times a second. Without one, the town is repainted once the
    /// hour has moved on a little, at most five times a second while the day is cycling, in the background.
    private func paintTown(_ dt: Float) {
        if let pane, !painting, pane.tick(dt, hour: hour) {
            showsView = true
            return
        }
        guard !showsView else { return }
        townAge += dt
        let moved = abs(hour - townHour)
        guard min(moved, 24 - moved) > 0.05, townAge > 0.2, !painting, pane != nil else { return }
        townHour = hour
        townAge = 0
        painting = true
        let light = light
        Task { [weak self] in
            let picture = await Task.detached { TownPicture.image(light) }.value
            guard let self else { return }
            painting = false
            guard !showsView, let image = picture.cgImage else { return }
            show(image)
        }
    }

    /// Puts `image` on the window's pane, flat, until a view is painted.
    private func show(_ image: CGImage) {
        pane?.showFlat(image)
    }

    private func setPoint(_ entity: Entity, color: SIMD3<Float>, lumens: Float, radius: Float) {
        var p = PointLightComponent(color: Daylight.color(color), intensity: lumens, attenuationRadius: radius)
        p.attenuationFalloffExponent = 2
        entity.components.set(p)
    }

    // MARK: - Structure

    private func buildFloor() {
        pivot.box(1.14, 0.1, 1.14, r: 0.03, Clay.matte(Tone.wood), at: [-0.01, -0.05, -0.01])
        for i in 0..<7 {
            let tone = i.isMultiple(of: 2) ? Tone.floor : Tone.floorLight
            pivot.box(1.04, 0.014, 0.146, r: 0.005, Clay.matte(tone, roughness: 0.7), at: [0, 0.007, -0.45 + Float(i) * 0.15])
        }
    }

    private func buildWalls() {
        let h = wallHeight
        let wall = Clay.matte(Tone.wall, roughness: 0.95)
        let o = opening
        pivot.box(0.05, h, 1.06, r: 0.01, wall, at: [-0.525, h / 2, -0.03])
        // The back wall in four pieces around the window.
        let x0: Float = -0.555, x1: Float = 0.495
        pivot.box(o.left - x0, h, 0.05, r: 0.004, wall, at: [(x0 + o.left) / 2, h / 2, -0.525])
        pivot.box(x1 - o.right, h, 0.05, r: 0.004, wall, at: [(o.right + x1) / 2, h / 2, -0.525])
        pivot.box(o.right - o.left, o.bottom, 0.05, r: 0.004, wall, at: [0, o.bottom / 2, -0.525])
        pivot.box(o.right - o.left, h - o.top, 0.05, r: 0.004, wall, at: [0, (o.top + h) / 2, -0.525])

        let wood = Clay.matte(Tone.wood)
        pivot.box(0.014, 0.045, 1.0, r: 0.004, wood, at: [-0.493, 0.0225, 0])
        pivot.box(1.0, 0.045, 0.014, r: 0.004, wood, at: [0, 0.0225, -0.493])
    }

    /// The window: the town painted on a pane just behind the glass.
    private func buildWindow() {
        let o = opening
        let width = o.right - o.left, height = o.top - o.bottom
        let c = windowCenter

        let pane = WindowPane(width: width, height: height, eye: framing.direction)
        pane.entity.position = [0, c.y, -0.545]
        pivot.addChild(pane.entity)
        self.pane = pane

        let frame = Clay.matte(Tone.frame, roughness: 0.6)
        let d: Float = 0.05
        pivot.box(width + 0.03, 0.018, d, r: 0.004, frame, at: [0, o.top, -0.525])
        pivot.box(0.018, height, d, r: 0.004, frame, at: [o.left, c.y, -0.525])
        pivot.box(0.018, height, d, r: 0.004, frame, at: [o.right, c.y, -0.525])
        for x in [-width / 6, width / 6] { pivot.box(0.014, height, 0.02, r: 0.004, frame, at: [x, c.y, -0.54]) }
        pivot.box(width, 0.012, 0.02, r: 0.004, frame, at: [0, o.top - 0.11, -0.54])

        // Mochi sits on the sill.
        pivot.box(width + 0.08, 0.025, 0.14, r: 0.006, frame, at: [0, o.bottom, -0.44])

        // A note taped to the middle pane, with a heart on it.
        let note = pivot.group(at: [-0.02, 0.53, -0.527], rotation: .z(0.04))
        note.box(0.1, 0.12, 0.003, r: 0.001, Clay.matte(Tone.paper, roughness: 1), at: .zero)
        let heart = Clay.matte(Tone.heart)
        for x: Float in [-0.006, 0.006] { note.sphere(0.008, heart, at: [x, 0.004, 0.002], scale: [1, 1, 0.2]) }
        note.box(0.013, 0.013, 0.002, r: 0, heart, at: [0, -0.002, 0.002], rotation: .z(.pi / 4))
    }

    private func buildFairyLights() {
        let material = Clay.glow(Tone.bulb, intensity: 4)
        let top = wallHeight - 0.04
        for i in 0..<13 {
            let t = Float(i) / 12
            let sag = 0.04 * abs(sin(t * .pi * 2))
            bulbs.append(pivot.sphere(0.01, material, at: [-0.47, top - sag, -0.47 + t * 0.94]))
        }
        // Draped along the curtain rod, in front of the curtains.
        let o = opening
        for i in 0...16 {
            let u = Float(i) / 16
            let x = o.left - 0.04 + u * (o.right - o.left + 0.08)
            let sag = 0.022 * abs(sin(u * .pi * 3))
            bulbs.append(pivot.sphere(0.009, material, at: [x, o.top + 0.04 - sag, -0.462]))
        }
    }

    // MARK: - Furniture

    private func buildRug() {
        pivot.cylinder(0.006, 0.22, Clay.matte(Tone.rugEdge, roughness: 1), at: [0.04, 0.016, 0.2])
        pivot.cylinder(0.008, 0.2, Clay.matte(Tone.rug, roughness: 1), at: [0.04, 0.019, 0.2])
    }

    /// Along the back wall under the window, pillow on the left, blanket over the right.
    private func buildBed() {
        let bed = pivot.group(at: [-0.04, 0.014, -0.315])
        bed.box(0.76, 0.1, 0.36, r: 0.02, Clay.matte(Tone.bedFrame), at: [0, 0.05, 0])
        bed.box(0.72, 0.07, 0.33, r: 0.03, Clay.matte(Tone.mattress, roughness: 1), at: [0, 0.13, 0])
        bed.box(0.44, 0.04, 0.35, r: 0.018, Clay.matte(Tone.blanket, roughness: 1), at: [0.15, 0.17, 0.005])
        bed.box(0.04, 0.08, 0.35, r: 0.018, Clay.matte(Tone.blanket, roughness: 1), at: [0.37, 0.13, 0.005])
        bed.box(0.15, 0.05, 0.25, r: 0.024, Clay.matte(Tone.pillow, roughness: 1), at: [-0.26, 0.19, -0.01], rotation: .y(0.08))
        bed.box(0.12, 0.012, 0.2, r: 0.005, Clay.matte(0xF6C69E, roughness: 1), at: [-0.05, 0.172, 0.04])
    }

    private func buildNightstand() {
        let n = pivot.group(at: [-0.37, 0.014, -0.02])
        let slat = Clay.matte(0xB84F30)
        n.box(0.13, 0.15, 0.13, r: 0.008, Clay.matte(Tone.crate), at: [0, 0.075, 0])
        for y: Float in [0.04, 0.09, 0.135] { n.box(0.134, 0.012, 0.134, r: 0.004, slat, at: [0, y, 0]) }

        n.cylinder(0.01, 0.03, Clay.matte(0x6D4C3A), at: [0, 0.155, 0])
        n.cylinder(0.08, 0.005, Clay.matte(0x6D4C3A), at: [0, 0.2, 0])
        // The web shade tapers from 0.035 to 0.06; a straight one of the average radius reads the same at this size.
        lampShade = n.cylinder(0.065, 0.0475, Clay.glow(Tone.shade, intensity: 0.2), at: [0, 0.255, 0])
        lampLight = n.group(at: [0.02, 0.26, 0.03])

        n.box(0.05, 0.03, 0.07, r: 0.004, Clay.matte(0x7C9A7E), at: [0.035, 0.165, 0.03], rotation: .y(0.2))
    }

    private func buildSillProps() {
        let plant = pivot.group(at: [-0.31, sillTop, -0.45])
        plant.cylinder(0.045, 0.022, Clay.matte(Tone.pot), at: [0, 0.022, 0])
        for i in 0..<7 {
            let a = Float(i) / 7 * 2 * .pi
            plant.sphere(0.045, Clay.matte(i.isMultiple(of: 2) ? Tone.leaf : Tone.leafDark),
                         at: [cos(a) * 0.012, 0.09 + Float(i % 3) * 0.015, sin(a) * 0.012],
                         scale: [0.18, 1.2, 0.08], rotation: .y(-a) * .z(-0.25 - Float(i % 3) * 0.1))
        }
        pivot.box(0.08, 0.016, 0.06, r: 0.004, Clay.matte(0xE3B45C), at: [-0.16, sillTop + 0.008, -0.45], rotation: .y(-0.15))
        pivot.box(0.07, 0.014, 0.055, r: 0.004, Clay.matte(0x6F8FB0), at: [-0.16, sillTop + 0.023, -0.45], rotation: .y(0.1))
        pivot.cylinder(0.03, 0.013, Clay.matte(0xF2E6D2, roughness: 0.4), at: [0.07, sillTop + 0.015, -0.45])
    }

    /// Curtains, the left wall's shelf, clock and pictures, and the things lying around on the floor.
    private func buildDecor() {
        Props.curtains(pivot, at: [0, 0.765, -0.48], width: opening.right - opening.left + 0.1, drop: 0.5)

        let wall: Float = -0.5
        Props.picture(pivot, at: [wall, 0.56, -0.34], width: 0.12, height: 0.09)
        Props.picture(pivot, at: [wall, 0.6, -0.19], width: 0.07, height: 0.09, sky: 0xBFD7E6, hill: 0xE3B45C, sun: 0xFBF1E3)
        setClock = Props.wallClock(pivot, at: [wall, 0.655, 0.27])
        Props.wallShelf(pivot, at: [wall, 0.48, 0.27], length: 0.3)
        Props.bookRow(pivot, at: [wall + 0.035, 0.487, 0.13], tones: [0xC0563A, 0x7C9A7E, 0xE3B45C, 0x9A7BB8, 0x6F8FB0],
                      rotation: .y(-.pi / 2))
        Props.cactus(pivot, at: [wall + 0.035, 0.487, 0.33])
        Props.candleJar(pivot, at: [wall + 0.04, 0.487, 0.39])
        candleLight = pivot.group(at: [wall + 0.08, 0.55, 0.39])

        Props.dresser(pivot, at: [-0.44, 0.014, 0.28], length: 0.24)
        Props.radio(pivot, at: [-0.44, 0.184, 0.2], rotation: .identity)
        Props.snakePlant(pivot, at: [-0.44, 0.184, 0.35], pot: 0xE9D9B8)
        Props.bookStack(pivot, at: [-0.43, 0.184, 0.28], tones: [0xE98A5B, 0xF2D3A0], rotation: .y(0.3))

        Props.catBed(pivot, at: catBed.at, scale: catBed.scale)
        Props.slippers(pivot, at: [-0.2, 0.014, -0.08], rotation: .y(-0.4))
        Props.catBowls(pivot, at: [0.38, 0.014, -0.05], rotation: .y(.pi / 2 - 0.3))
        Props.toyMouse(pivot, at: [0.0, 0.023, 0.27], rotation: .y(0.8))
        Props.bookStack(pivot, at: [-0.22, 0.014, 0.42], tones: [0x6F8FB0, 0xC0563A, 0xE3B45C], rotation: .y(-0.4))
        Props.plush(pivot, at: [-0.16, 0.18, -0.42], rotation: .y(-0.8))
    }

    private func buildLighting() {
        receiveAmbient(from: ibl)
        Self.castShadow(sun)
        // In the pivot, so the patch of sun through the window turns with the room.
        pivot.addChild(sun)
        // Soft light from the viewer's side, so the room reads even with the sun behind the window wall.
        fill.look(at: .zero, from: [1.5, 1.4, 1.6], relativeTo: nil)
        root.addChild(fill)
        skyLight = pivot.group(at: [0, 0.5, -0.38])
        fairyLight = pivot.group(at: [-0.2, 0.7, -0.3])
        addBloom()
    }
}
