import FeatureGames
import RealityKit
import SwiftUI
import UIKit

/// The close-up corner of floor the feed, water and brush games are played on, and the laser when it leaves the room:
/// a floor and a wall dressed as the picked scenery, its own warm light and camera, and Mochi in her coat, borrowed
/// from the room for as long as the game lasts. The camera sits low, near her eye line, so she can look up at the
/// player.
final class TabletopRoom: CatRoom {
    static let floorTop: Float = 0.02
    static let catScale: Float = 0.68
    /// The wall behind her, along z.
    private static let wallAt: Float = -0.42
    /// The row of props along the wall; the cat and what she plays with sit in front of it.
    private static let backRow: Float = wallAt + 0.06

    let camera = PerspectiveCamera()
    private(set) var scenery: GameScenery
    private let ibl = Entity()
    private let sun = Entity()
    private let fill = Entity()
    private var dressing: Entity?

    override var framing: Framing {
        Framing(target: [0, 0.07, 0.02], direction: simd_normalize([0.1, 0.3, 1]), far: 3.2, near: 3.2)
    }
    override var yawLimit: Float { 0 }

    /// Ready for a game once it is in a view and Mochi has loaded into it.
    var isReady: Bool { root.scene != nil && walker != nil }

    init(scenery: GameScenery) {
        self.scenery = scenery
        super.init()
        camera.camera.fieldOfViewInDegrees = 22
        root.addChild(camera)
        let framing = framing
        camera.look(at: framing.target, from: framing.target + framing.direction * framing.far, relativeTo: nil)

        dressing = Self.dress(pivot, as: scenery)
        buildCat(at: [0, Self.floorTop + 0.003, -0.1], rests: [.pi], scale: Self.catScale, wandering: false)
        buildLighting()
        buildMotes()
    }

    /// Swaps the floor, wall and props for `next`'s, in place: the game on it carries on.
    func dress(_ next: GameScenery) {
        guard next != scenery, next.isCorner else { return }
        scenery = next
        dressing?.removeFromParent()
        let built = Self.dress(pivot, as: next)
        if let iblReceiver { built.forEachDescendant { $0.components.set(iblReceiver) } }
        dressing = built
        light(for: next)
    }

    private func buildLighting() {
        receiveAmbient(from: ibl)
        Self.castShadow(sun)
        sun.look(at: .zero, from: [-0.6, 1.5, 0.8], relativeTo: nil)
        root.addChild(sun)
        fill.look(at: .zero, from: [1.5, 1.2, 1.6], relativeTo: nil)
        root.addChild(fill)
        light(for: scenery)
    }

    private func light(for scenery: GameScenery) {
        let tones = Self.tones(scenery)
        var sunLight = DirectionalLightComponent(color: UIColor(hex: tones.sun), intensity: tones.intensity)
        sunLight.isRealWorldProxy = false
        sun.components.set(sunLight)
        fill.components.set(DirectionalLightComponent(color: UIColor(hex: 0xFFE2C4), intensity: 200))
        guard let image = Self.gradientImage(top: Daylight.rgb(tones.sky), bottom: Daylight.rgb(tones.ground)) else {
            return
        }
        Task { [weak self] in
            guard let env = try? await EnvironmentResource(equirectangular: image), let self,
                  self.scenery == scenery else { return }
            ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.4))
        }
    }

    private static func tones(_ scenery: GameScenery) -> (sun: UInt32, intensity: Float, sky: UInt32, ground: UInt32) {
        switch scenery {
        case .room, .rug: (0xFFE2B8, 320, 0xFFE7C4, 0xB97A45)
        case .kitchen: (0xFFF0D8, 340, 0xFFF4E4, 0xC9A27A)
        case .garden: (0xFFF4DC, 380, 0xE8F2D8, 0x8F9A5E)
        }
    }

    /// The floor, the wall behind her and a few props, all clear of the play area in front of her.
    private static func dress(_ pivot: Entity, as scenery: GameScenery) -> Entity {
        let g = pivot.group()
        let top = floorTop
        switch scenery {
        case .room, .rug:
            g.box(3, 0.04, 3, r: 0.002, Clay.matte(0xCF8E58, roughness: 0.7), at: [0, 0, 0])
            g.cylinder(0.002, 0.42, Clay.matte(0xF3E6D2, roughness: 1), at: [0, top + 0.001, 0.02])
            g.cylinder(0.0024, 0.36, Clay.matte(0xE9C9A0, roughness: 1), at: [0, top + 0.0012, 0.02])
            wall(g, tone: 0xF3E2CC, skirting: 0xE6CDAE)
            window(g, at: [0.2, 0.25, wallAt + 0.012])
            Props.bookStack(g, at: [0.14, top, backRow], tones: [0x6F8FB0, 0xE98A5B, 0x93A86A], rotation: .identity)
            Props.snakePlant(g, at: [-0.36, top, backRow])
            Props.plush(g, at: [0.36, top, backRow], rotation: .identity)
        case .kitchen:
            g.box(3, 0.04, 3, r: 0.002, Clay.matte(0xD9AE78, roughness: 0.8), at: [0, 0, 0])
            kitchen(g)
        case .garden:
            g.box(3, 0.04, 3, r: 0.002, Clay.matte(0xB98A5E, roughness: 0.8), at: [0, 0, 0])
            for z in stride(from: Float(-0.36), through: 0.4, by: 0.08) {
                g.box(1.2, 0.002, 0.004, r: 0.001, Clay.matte(0x9C7048, roughness: 1), at: [0, top + 0.001, z])
            }
            // A hedge for a wall, in soft lumps.
            g.box(1.6, 0.3, 0.1, r: 0.04, Clay.matte(0x6F8A4E, roughness: 1), at: [0, top + 0.15, wallAt])
            for i in 0..<9 {
                let x = -0.64 + Float(i) * 0.16
                g.sphere(0.09, Clay.matte(i % 2 == 0 ? 0x93A86A : 0x7F9A5A, roughness: 1),
                         at: [x, top + 0.3, wallAt + 0.01], scale: [1, 0.8, 0.7])
            }
            Props.snakePlant(g, at: [-0.36, top, -0.3], pot: 0xD8653F)
            Props.cactus(g, at: [0.36, top, -0.3])
            Props.toyMouse(g, at: [0.3, top, 0.02], rotation: .identity)
        }
        return g
    }

    /// The kitchen's baked wall and floor: two unlit pictures, the wall standing behind the rug the cat sits on.
    static let kitchenWall: Float = -0.7
    private static let kitchenFloor: (width: Float, depth: Float) = (1.68, 1.26)
    private static let kitchenWallSize: (width: Float, height: Float) = (0.8, 0.88)

    private static func kitchen(_ g: Entity) {
        let back = kitchenWall
        g.picture("kitchen_floor", width: kitchenFloor.width, height: kitchenFloor.depth, lying: true,
                  at: [0, floorTop + 0.001, back + kitchenFloor.depth / 2])
        g.picture("kitchen_wall", width: kitchenWallSize.width, height: kitchenWallSize.height, lying: false,
                  at: [0, floorTop + kitchenWallSize.height / 2, back])
    }

    private static func wall(_ g: Entity, tone: UInt32, skirting: UInt32) {
        g.box(1.6, 1.2, 0.02, r: 0.004, Clay.matte(tone, roughness: 0.9), at: [0, floorTop + 0.6, wallAt])
        g.box(1.6, 0.03, 0.012, r: 0.003, Clay.matte(skirting, roughness: 0.8), at: [0, floorTop + 0.015, wallAt + 0.014])
        g.box(1.6, 0.17, 0.008, r: 0.003, Clay.matte(skirting, roughness: 0.85), at: [0, floorTop + 0.115, wallAt + 0.012])
        g.box(1.6, 0.008, 0.014, r: 0.002, Clay.matte(0xFFF3E2, roughness: 0.7), at: [0, floorTop + 0.2, wallAt + 0.014])
    }

    /// A small bright window, the soft light the corner seems lit from.
    private static func window(_ g: Entity, at position: SIMD3<Float>) {
        g.box(0.16, 0.13, 0.008, r: 0.004, Clay.matte(0xFFF3E2, roughness: 0.6), at: position)
        g.box(0.14, 0.11, 0.004, r: 0.002, Clay.glow(0xFFE2B0, intensity: 1.2), at: position + [0, 0, 0.005])
        g.box(0.004, 0.11, 0.006, r: 0.001, Clay.matte(0xFFF3E2, roughness: 0.6), at: position + [0, 0, 0.007])
    }

    /// Hands Mochi back to `home` and stops driving this corner.
    func leave(to home: CatRoom?) {
        stop()
        home?.adoptCat()
    }
}

/// The corner as a full-screen view over the warm backdrop; it takes no touches, the game's layer does.
struct TabletopView: View {
    let room: TabletopRoom

    var body: some View {
        ZStack {
            WarmBackdrop(drifts: false)
            RealityView { content in
                content.camera = .virtual
                content.add(room.root)
                room.start(updatesFrom: content, viewer: room.camera, beforeProjecting: { _ in }, onFrame: { _ in })
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Entity {
    /// A bundled image on an unlit quad: standing and facing +z, or lying on the floor with its top toward -z.
    @discardableResult
    func picture(_ name: String, width: Float, height: Float, lying: Bool, at position: SIMD3<Float>,
                 transparent: Bool = false) -> ModelEntity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "webp"),
              let image = UIImage(contentsOfFile: url.path)?.cgImage,
              let texture = try? TextureResource(image: image, options: .init(semantic: .color)) else { return nil }
        var material = UnlitMaterial(applyPostProcessToneMap: false)
        material.color = .init(tint: .white, texture: .init(texture))
        if transparent { material.blending = .transparent(opacity: .init(floatLiteral: 1)) }
        let mesh = lying ? MeshResource.generatePlane(width: width, depth: height) : MeshResource.generatePlane(width: width, height: height)
        let quad = ModelEntity(mesh: mesh, materials: [material])
        quad.position = position
        addChild(quad)
        return quad
    }
}
