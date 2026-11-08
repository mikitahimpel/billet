import RealityKit
import SwiftUI
import UIKit

/// The close-up corner of floor the feed, water and brush games are played on: a wooden floor with a rug, its own
/// warm light and camera, and Mochi in her coat, borrowed from the room for as long as the game lasts.
final class TabletopRoom: CatRoom {
    static let floorTop: Float = 0.02
    static let catScale: Float = 0.68

    let camera = PerspectiveCamera()
    private let ibl = Entity()
    private let sun = Entity()
    private let fill = Entity()

    override var framing: Framing {
        Framing(target: [0, 0.06, 0.04], direction: simd_normalize([0.35, 0.8, 1]), far: 3.2, near: 3.2)
    }
    override var yawLimit: Float { 0 }

    /// Ready for a game once it is in a view and Mochi has loaded into it.
    var isReady: Bool { root.scene != nil && walker != nil }

    override init() {
        super.init()
        camera.camera.fieldOfViewInDegrees = 22
        root.addChild(camera)
        let framing = framing
        camera.look(at: framing.target, from: framing.target + framing.direction * framing.far, relativeTo: nil)

        pivot.box(3, 0.04, 3, r: 0.002, Clay.matte(0xCF8E58, roughness: 0.7), at: [0, 0, 0])
        pivot.cylinder(0.002, 0.42, Clay.matte(0xF3E6D2, roughness: 1), at: [0.0, Self.floorTop + 0.001, 0.02])
        pivot.cylinder(0.0024, 0.36, Clay.matte(0xE9C9A0, roughness: 1), at: [0.0, Self.floorTop + 0.0012, 0.02])
        buildCat(at: [0, Self.floorTop + 0.003, -0.1], rests: [0], scale: Self.catScale, wandering: false)
        buildLighting()
    }

    private func buildLighting() {
        receiveAmbient(from: ibl)
        if let image = Self.gradientImage(top: Daylight.rgb(0xFFE7C4), bottom: Daylight.rgb(0xB97A45)) {
            Task { [weak self] in
                guard let env = try? await EnvironmentResource(equirectangular: image), let self else { return }
                ibl.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: -0.4))
            }
        }
        var sunLight = DirectionalLightComponent(color: UIColor(hex: 0xFFE2B8), intensity: 320)
        sunLight.isRealWorldProxy = false
        sun.components.set(sunLight)
        Self.castShadow(sun)
        sun.look(at: .zero, from: [-0.6, 1.5, 0.8], relativeTo: nil)
        root.addChild(sun)
        fill.components.set(DirectionalLightComponent(color: UIColor(hex: 0xFFE2C4), intensity: 200))
        fill.look(at: .zero, from: [1.5, 1.2, 1.6], relativeTo: nil)
        root.addChild(fill)
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
