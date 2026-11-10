import OurioShared
import RealityKit
import SwiftUI
import UIKit
import WindowViews

private enum Tone {
    static let wall: UInt32 = 0xF6E4C8
    static let wood: UInt32 = 0xB46C3C
    static let woodDark: UInt32 = 0x8C4F2B
    static let woodLight: UInt32 = 0xCF8E58
    static let bedFrame: UInt32 = 0xE8D2B2
    static let mattress: UInt32 = 0xFBF0DE
    static let blanket: UInt32 = 0xE98A5B
    static let pillow: UInt32 = 0xF4E2C8
    static let crate: UInt32 = 0xD8653F
    static let shade: UInt32 = 0xF7ECD8
    static let rug: UInt32 = 0xDDB98A
    static let rugEdge: UInt32 = 0xC39A69
    static let leaf: UInt32 = 0x93A86A
    static let leafDark: UInt32 = 0x6F8A4E
    static let pot: UInt32 = 0xC7744A
    static let bulb: UInt32 = 0xFFD27A
    static let paper: UInt32 = 0xF6EFE2
    static let heart: UInt32 = 0xE0554A
}

/// A bedroom with a window onto a living town, lit by the real local hour. The window is a hole in the wall: the
/// town is drawn flat behind the room at screen pixels (`windowView`, under the room in HomeView), told each frame
/// where the window lands. TownPicture fills the hole on its own plane until that view shows or where it isn't hosted.
final class CityRoomScene: CatRoom {
    private enum Clock {
        case live
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

    /// Shown under the room at the same size.
    let windowView = CityWindowView()
    /// The town in the hole until `windowView` shows.
    private var fallback: ModelEntity?
    private var fallbackTexture: TextureResource?
    private var choice = WindowChoice.current
    private var weather = WindowChoice.weather
    private var choiceAge: Float = .infinity
    private var lampsOn = false
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
    private var reduceMotion = UIAccessibility.isReduceMotionEnabled
    private let ibl = Entity()

    override init() {
        super.init()
        useBakedShell(named: "City_shell")
        buildFloor()
        buildWalls()
        buildWindow()
        buildFairyLights()
        buildRug()
        addContactShadow(named: "city_contact", x0: -0.58, z0: -0.58, x1: 0.56, z1: 0.56, y: 0.017)
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

        let lamps = smoothstep(darkness, 0.2, 0.7)
        lampsOn = lamps > 0.5
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
        if isBaked { tintShell(BakedShell.tint(light)) }
    }

    private func applyAmbient() {
        guard let environment else { return }
        ibl.components.set(ImageBasedLightComponent(source: .single(environment),
                                                    intensityExponent: log2(max(light.env, 0.05) / 0.85) - 0.4))
    }

    /// Keeps the flat view on the chosen look and its life moving. Until it shows, the town is repainted once the hour
    /// has moved on a little, at most five times a second while the day is cycling, in the background.
    private func paintTown(_ dt: Float) {
        choiceAge += dt
        // The settings and the hour's look are checked once a second rather than every frame.
        if choiceAge > 1 {
            choiceAge = 0
            choice = WindowChoice.current
            weather = WindowChoice.weather
            reduceMotion = UIAccessibility.isReduceMotionEnabled
            windowView.show(choice, hour: hour, weather: weather, lampOn: lampsOn, reduceMotion: reduceMotion)
        }
        windowView.tick(Double(dt), hour: hour)
        let showsView = windowView.isReady && windowView.window != nil
        fallback?.isEnabled = !showsView
        guard !showsView else { return }
        townAge += dt
        let moved = abs(hour - townHour)
        guard min(moved, 24 - moved) > 0.05, townAge > 0.2, !painting else { return }
        townHour = hour
        townAge = 0
        painting = true
        let light = light
        Task { [weak self] in
            let picture = await Task.detached { TownPicture.image(light) }.value
            guard let self else { return }
            painting = false
            guard let image = picture.cgImage else { return }
            show(image)
        }
    }

    private func show(_ image: CGImage) {
        guard let fallback else { return }
        if let fallbackTexture {
            try? fallbackTexture.replace(withImage: image, options: .init(semantic: .color))
        } else if let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            fallbackTexture = texture
            var material = UnlitMaterial(color: .white, applyPostProcessToneMap: false)
            material.color = .init(tint: .white, texture: .init(texture))
            fallback.model?.materials = [material]
        }
    }

    // MARK: - The window on screen

    override func start(updatesFrom content: RealityViewCameraContent, viewer: Entity,
                        beforeProjecting: @escaping (Float) -> Void, onFrame: @escaping (CGPoint?) -> Void) {
        super.start(updatesFrom: content, viewer: viewer, beforeProjecting: beforeProjecting) { [weak self] head in
            onFrame(head)
            self?.placeWindow(content)
        }
    }

    /// Tells the flat view where the window is on screen this frame, after the camera has moved: the glass as it is
    /// and as it would be with the room unturned, which the planes' parallax runs between, and the hole in the wall's
    /// front face, which the view is clipped to. The wall around the hole, drawn over the view, hides its edges.
    private func placeWindow(_ content: RealityViewCameraContent) {
        let o = opening
        let corners: [SIMD2<Float>] = [[o.left, o.top], [o.right, o.top], [o.right, o.bottom], [o.left, o.bottom]]
        let glass = corners.map { SIMD3<Float>($0.x, $0.y, -0.54) }
        let face = corners.map { SIMD3<Float>($0.x, $0.y, -0.5) }
        let project = { (point: SIMD3<Float>) in content.project(point: point, to: .local) }
        let window = glass.compactMap { project(pivot.convert(position: $0, to: nil)) }
        let home = glass.compactMap { project(root.convert(position: $0, to: nil)) }
        let hole = face.compactMap { project(pivot.convert(position: $0, to: nil)) }
        guard window.count == 4, hole.count == 4 else {
            return windowView.place(window: [], home: [], hole: [])
        }
        windowView.place(window: window, home: home.count == 4 ? home : window, hole: hole)
    }

    /// One material per tone and roughness, shared by every part built from it.
    private var mattes: [SIMD2<UInt32>: PhysicallyBasedMaterial] = [:]

    private func matte(_ hex: UInt32, roughness: Float = 0.82) -> PhysicallyBasedMaterial {
        let key = SIMD2(hex, roughness.bitPattern)
        if let material = mattes[key] { return material }
        let material = Clay.matte(hex, roughness: roughness)
        mattes[key] = material
        return material
    }

    private func setPoint(_ entity: Entity, color: SIMD3<Float>, lumens: Float, radius: Float) {
        guard !isBaked else { return }
        var p = PointLightComponent(color: Daylight.color(color), intensity: lumens, attenuationRadius: radius)
        p.attenuationFalloffExponent = 2
        entity.components.set(p)
    }

    // MARK: - Structure

    private func buildFloor() {
        pivot.box(1.14, 0.1, 1.14, r: 0.03, matte(Tone.woodDark), at: [-0.01, -0.05, -0.01])
        for i in 0..<7 {
            let tone = i.isMultiple(of: 2) ? Tone.wood : Tone.woodLight
            pivot.box(1.04, 0.014, 0.146, r: 0.005, matte(tone, roughness: 0.7), at: [0, 0.007, -0.45 + Float(i) * 0.15])
        }
    }

    private func buildWalls() {
        let h = wallHeight
        let wall = matte(Tone.wall, roughness: 0.95)
        let o = opening
        pivot.box(0.05, h, 1.06, r: 0.01, wall, at: [-0.525, h / 2, -0.03])
        // The back wall in four pieces around the window; the window's trim covers their seams.
        let x0: Float = -0.555, x1: Float = 0.495
        pivot.box(o.left - x0, h, 0.05, r: 0.01, wall, at: [(x0 + o.left) / 2, h / 2, -0.525])
        pivot.box(x1 - o.right, h, 0.05, r: 0.01, wall, at: [(o.right + x1) / 2, h / 2, -0.525])
        pivot.box(o.right - o.left, o.bottom, 0.05, r: 0.01, wall, at: [0, o.bottom / 2, -0.525])
        pivot.box(o.right - o.left, h - o.top, 0.05, r: 0.01, wall, at: [0, (o.top + h) / 2, -0.525])

        let wood = matte(Tone.wood)
        pivot.box(0.014, 0.05, 1.0, r: 0.004, wood, at: [-0.493, 0.025, 0])
        pivot.box(1.0, 0.05, 0.014, r: 0.004, wood, at: [0, 0.025, -0.493])

        // Corner posts and top beams.
        for (x, z) in [(-0.535, 0.52), (-0.535, -0.535), (0.52, -0.535)] as [(Float, Float)] {
            pivot.box(0.075, h + 0.06, 0.075, r: 0.012, wood, at: [x, (h + 0.06) / 2, z])
        }
        pivot.box(0.085, 0.065, 1.13, r: 0.015, wood, at: [-0.535, h + 0.02, -0.01])
        pivot.box(1.13, 0.065, 0.085, r: 0.015, wood, at: [-0.01, h + 0.02, -0.535])
    }

    private func buildWindow() {
        let o = opening
        let width = o.right - o.left, height = o.top - o.bottom
        let c = windowCenter

        let fallback = ModelEntity(mesh: .generatePlane(width: width, height: height),
                                   materials: [UnlitMaterial(color: UIColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1),
                                                             applyPostProcessToneMap: false)])
        fallback.position = [0, c.y, -0.545]
        pivot.addChild(fallback)
        self.fallback = fallback

        // Like the first room's round window: a wood ring, a lighter bead round the glass and wood muntins.
        let frame = matte(Tone.wood, roughness: 0.6)
        let bead = matte(Tone.woodLight, roughness: 0.6)
        let d: Float = 0.05
        pivot.box(width + 0.05, 0.03, d, r: 0.008, frame, at: [0, o.top + 0.005, -0.525])
        pivot.box(0.03, height, d, r: 0.008, frame, at: [o.left - 0.005, c.y, -0.525])
        pivot.box(0.03, height, d, r: 0.008, frame, at: [o.right + 0.005, c.y, -0.525])
        pivot.box(width, 0.008, 0.03, r: 0.003, bead, at: [0, o.top - 0.004, -0.53])
        for x in [o.left + 0.004, o.right - 0.004] { pivot.box(0.008, height, 0.03, r: 0.003, bead, at: [x, c.y, -0.53]) }
        for x in [-width / 6, width / 6] { pivot.box(0.014, height, 0.014, r: 0.004, frame, at: [x, c.y, -0.54]) }
        pivot.box(width, 0.014, 0.014, r: 0.004, frame, at: [0, o.top - 0.11, -0.54])

        // Mochi sits on the sill, a light wood with a rounded nose, an apron under it and two corbels.
        pivot.box(width + 0.08, 0.025, 0.14, r: 0.007, bead, at: [0, o.bottom, -0.44])
        pivot.box(width + 0.04, 0.034, 0.024, r: 0.008, frame, at: [0, o.bottom - 0.029, -0.382])
        for x in [-width / 2 - 0.03, width / 2 + 0.03] {
            pivot.box(0.022, 0.05, 0.07, r: 0.01, frame, at: [x, o.bottom - 0.037, -0.465])
        }

        // A note taped to the middle pane, with a heart on it.
        let note = pivot.group(at: [-0.02, 0.53, -0.527], rotation: .z(0.04))
        note.box(0.1, 0.12, 0.003, r: 0.001, matte(Tone.paper, roughness: 1), at: .zero)
        let heart = matte(Tone.heart)
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
        pivot.cylinder(0.006, 0.22, matte(Tone.rugEdge, roughness: 1), at: [0.04, 0.016, 0.2])
        pivot.cylinder(0.008, 0.2, matte(Tone.rug, roughness: 1), at: [0.04, 0.019, 0.2])
    }

    /// Along the back wall under the window, pillow on the left, blanket over the right.
    private func buildBed() {
        let bed = pivot.group(at: [-0.04, 0.014, -0.315])
        bed.box(0.76, 0.1, 0.36, r: 0.02, matte(Tone.bedFrame), at: [0, 0.05, 0])
        bed.box(0.72, 0.07, 0.33, r: 0.03, matte(Tone.mattress, roughness: 1), at: [0, 0.13, 0])
        bed.box(0.44, 0.04, 0.35, r: 0.018, matte(Tone.blanket, roughness: 1), at: [0.15, 0.17, 0.005])
        bed.box(0.04, 0.08, 0.35, r: 0.018, matte(Tone.blanket, roughness: 1), at: [0.37, 0.13, 0.005])
        bed.box(0.15, 0.05, 0.25, r: 0.024, matte(Tone.pillow, roughness: 1), at: [-0.26, 0.19, -0.01], rotation: .y(0.08))
        bed.box(0.12, 0.012, 0.2, r: 0.005, matte(0xF6C69E, roughness: 1), at: [-0.05, 0.172, 0.04])
    }

    private func buildNightstand() {
        let n = pivot.group(at: [-0.37, 0.014, -0.02])
        let slat = matte(0xB84F30)
        n.box(0.13, 0.15, 0.13, r: 0.008, matte(Tone.crate), at: [0, 0.075, 0])
        for y: Float in [0.04, 0.09, 0.135] { n.box(0.134, 0.012, 0.134, r: 0.004, slat, at: [0, y, 0]) }

        n.cylinder(0.01, 0.03, matte(0x6D4C3A), at: [0, 0.155, 0])
        n.cylinder(0.08, 0.005, matte(0x6D4C3A), at: [0, 0.2, 0])
        // The web shade tapers from 0.035 to 0.06; a straight one of the average radius reads the same at this size.
        lampShade = n.cylinder(0.065, 0.0475, Clay.glow(Tone.shade, intensity: 0.2), at: [0, 0.255, 0])
        lampLight = n.group(at: [0.02, 0.26, 0.03])

        n.box(0.05, 0.03, 0.07, r: 0.004, matte(0x7C9A7E), at: [0.035, 0.165, 0.03], rotation: .y(0.2))
    }

    private func buildSillProps() {
        let plant = pivot.group(at: [-0.31, sillTop, -0.45])
        plant.cylinder(0.045, 0.022, matte(Tone.pot), at: [0, 0.022, 0])
        for i in 0..<7 {
            let a = Float(i) / 7 * 2 * .pi
            plant.sphere(0.045, matte(i.isMultiple(of: 2) ? Tone.leaf : Tone.leafDark),
                         at: [cos(a) * 0.012, 0.09 + Float(i % 3) * 0.015, sin(a) * 0.012],
                         scale: [0.18, 1.2, 0.08], rotation: .y(-a) * .z(-0.25 - Float(i % 3) * 0.1))
        }
        pivot.box(0.08, 0.016, 0.06, r: 0.004, matte(0xE3B45C), at: [-0.16, sillTop + 0.008, -0.45], rotation: .y(-0.15))
        pivot.box(0.07, 0.014, 0.055, r: 0.004, matte(0x6F8FB0), at: [-0.16, sillTop + 0.023, -0.45], rotation: .y(0.1))
        pivot.cylinder(0.03, 0.013, matte(0xF2E6D2, roughness: 0.4), at: [0.07, sillTop + 0.015, -0.45])
    }

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
