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
        Framing(target: [0, 0.07, 0.02], direction: simd_normalize([0.1, 0.24, 1]), far: 3.2, near: 3.2)
    }
    override var yawLimit: Float { 0 }

    /// Ready for a game once it is in a view and Mochi has loaded into it.
    var isReady: Bool { root.scene != nil && walker != nil }

    init(scenery: GameScenery) {
        self.scenery = scenery
        super.init()
        camera.camera.fieldOfViewInDegrees = 22
        // The corner is a metre across seen from about three: a tight depth range keeps the 1 mm steps of rugs and
        // worktops from fighting.
        camera.camera.near = 1.2
        camera.camera.far = 7
        root.addChild(camera)
        let framing = framing
        camera.look(at: framing.target, from: framing.target + framing.direction * framing.far, relativeTo: nil)

        dressing = Self.dress(pivot, as: scenery)
        buildCat(at: [0, Self.floorTop + 0.003, -0.1], rests: [.pi], scale: Self.catScale, wandering: false)
        buildLighting()
        buildMotes()
    }

    /// The corner's camera stands still; a game's framing is the only thing that moves it.
    func placeCamera(_ dt: Float) {
        let framing = framing
        var pose = CameraPose(eye: framing.target + framing.direction * framing.far, target: framing.target)
        if let cameraAdjust { pose = cameraAdjust(dt, pose) }
        guard pose != placed else { return }
        placed = pose
        camera.look(at: pose.target, from: pose.eye, relativeTo: nil)
    }
    private var placed: CameraPose?

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
        }
    }

    /// The floor, the wall behind her and a few props, all clear of the play area in front of her.
    private static func dress(_ pivot: Entity, as scenery: GameScenery) -> Entity {
        if scenery == .kitchen { return KitchenSet.build(in: pivot, floorTop: floorTop) }
        let g = pivot.group()
        let top = floorTop
        switch scenery {
        case .rug:
            rugCorner(g)
        case .room:
            g.box(3, 0.04, 3, r: 0.002, Clay.matte(0xCF8E58, roughness: 0.7), at: [0, 0, 0])
            g.cylinder(0.0014, 0.42, Clay.matte(0xF3E6D2, roughness: 1), at: [0, top + 0.0007, 0.02])
            g.cylinder(0.0022, 0.36, Clay.matte(0xE9C9A0, roughness: 1), at: [0, top + 0.0011, 0.02])
            wall(g, tone: 0xF3E2CC, skirting: 0xE6CDAE)
            window(g, at: [0.2, 0.25, wallAt + 0.012])
            Props.bookStack(g, at: [0.14, top, backRow], tones: [0x6F8FB0, 0xE98A5B, 0x93A86A], rotation: .identity)
            Props.snakePlant(g, at: [-0.36, top, backRow])
            Props.plush(g, at: [0.36, top, backRow], rotation: .identity)
        case .kitchen:
            break
        }
        return g
    }

    /// The brush's corner: a warm rug under her, two walls, and a cushion, a basket, a plant and a lamp set round the
    /// edge of what the close camera shows. A few clay primitives and baked blobs, nothing that casts a shadow.
    private static func rugCorner(_ g: Entity) {
        let top = floorTop
        let side: Float = -0.27
        g.box(3, 0.04, 3, r: 0.002, Clay.matte(0xCF8E58, roughness: 0.7), at: [0, 0, 0])
        g.cylinder(0.0014, 0.3, Clay.matte(0xF3E6D2, roughness: 1), at: [0, top + 0.0007, -0.02], scale: [1.25, 1, 1])
        g.cylinder(0.0022, 0.25, Clay.matte(0xE9B8A0, roughness: 1), at: [0, top + 0.0011, -0.02], scale: [1.25, 1, 1])
        g.cylinder(0.0028, 0.17, Clay.matte(0xF3E6D2, roughness: 1), at: [0, top + 0.0014, -0.02], scale: [1.25, 1, 1])
        wall(g, tone: 0xF3E2CC, skirting: 0xE6CDAE)
        let left = g.group(at: [side, 0, 0], rotation: .y(.pi / 2))
        left.box(1.2, 1.2, 0.02, r: 0.004, Clay.matte(0xEBD3B4, roughness: 0.9), at: [0, top + 0.6, 0])
        left.box(1.2, 0.03, 0.012, r: 0.003, Clay.matte(0xE6CDAE, roughness: 0.8), at: [0, top + 0.015, 0.014])
        window(g, at: [0.12, 0.27, wallAt + 0.012])
        g.contactBlob(at: [-0.2, top, wallAt + 0.04], width: 0.12, depth: 0.1)
        Props.lamp(g, at: [-0.2, top, wallAt + 0.05])
        g.contactBlob(at: [0.19, top, wallAt + 0.05], width: 0.1, depth: 0.09)
        Props.snakePlant(g, at: [0.19, top, wallAt + 0.05], pot: 0xD8653F)
        g.contactBlob(at: [-0.19, top, -0.2], width: 0.14, depth: 0.12)
        Props.basket(g, at: [-0.19, top, -0.2])
        g.contactBlob(at: [0.2, top, -0.2], width: 0.14, depth: 0.12)
        Props.cushion(g, at: [0.2, top, -0.2], tone: 0xE98A5B)
        Props.bookStack(g, at: [0.0, top, wallAt + 0.06], tones: [0x6F8FB0, 0xE98A5B, 0x93A86A], rotation: .identity)
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

/// The one view corners are drawn in, for the app's life, over the warm backdrop; it takes no touches, the game's layer
/// does. A RealityView that goes away takes the GPU side of what it drew, shared meshes and materials among it, so a
/// corner built in a new view after that drew nothing for minutes: each corner swaps its root into this view instead.
/// While no corner is shown it holds nothing, shrunk to one point and transparent.
struct CornerStage: View {
    let controller: RoomController

    var body: some View {
        let room = controller.corner
        ZStack {
            if room != nil { WarmBackdrop(drifts: false) }
            if !controller.isStandIn {
                RealityView { content in
                    content.camera = .virtual
                    Self.show(room, in: content)
                } update: { content in
                    Self.show(room, in: content)
                }
            }
            // A soft shade at the corners: the corner reads as a space, the middle stays as bright as it was.
            if room != nil {
                RadialGradient(colors: [.clear, Color.honeyDeep.opacity(0.22)], center: .center, startRadius: 220, endRadius: 560)
            }
        }
        .frame(width: room == nil ? 1 : nil, height: room == nil ? 1 : nil)
        .opacity(room == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: room == nil)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func show(_ room: TabletopRoom?, in content: RealityViewCameraContent) {
        for entity in Array(content.entities) where entity !== room?.root { content.remove(entity) }
        guard let room, !content.entities.contains(where: { $0 === room.root }) else { return }
        content.add(room.root)
        room.start(on: content, viewer: room.camera, beforeProjecting: { [weak room] dt in room?.placeCamera(dt) }, onFrame: { _ in })
    }
}
