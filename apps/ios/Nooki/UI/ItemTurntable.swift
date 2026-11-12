import FeatureShop
import Observation
import RealityKit
import SwiftUI
import UIKit

/// The 3D turntable of the Shop's item sheet. RealityKit stays in the app, so `FeatureShop` gets it as `ItemPreview`.
private struct ItemRealityPreview: View {
    let item: ShopItem
    let turntable: ItemTurntable

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            turntable.attach(to: content, item: item)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

@Observable
final class ItemTurntable: ItemPreview {
    /// True once the scene has drawn a few frames with the model loaded (hidden), so the still can give way to it.
    var isDrawn = false
    /// Set as the still fades: the model fades in over it, and only starts turning once it has.
    @ObservationIgnored var isRevealed = false
    @ObservationIgnored private var isModelReady = false
    @ObservationIgnored private var framesDrawn = 0
    @ObservationIgnored private var shown: Float = 0

    /// Vertical padding the still gets inside the stage; the camera allows for it.
    static let thumbnailInset = ItemStage.thumbnailInset
    static let stageHeight = Float(ItemStage.height)

    @ObservationIgnored private let pivot = Entity()
    @ObservationIgnored private let camera = PerspectiveCamera()
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored var isDragging = false
    @ObservationIgnored private var angle: Float = 0
    @ObservationIgnored private var hop: Float = 1

    /// Called from `RealityView`'s make closure. Safe to run more than once: the pivot (and
    /// whatever is already loaded into it) simply moves into the newest scene.
    func attach(to content: RealityViewCameraContent, item: ShopItem) {
        let scene = Entity()
        scene.addChild(pivot)
        content.add(scene)
        content.add(camera)
        content.add(Self.makeSun())
        if let ambient = Self.makeAmbient() {
            content.add(ambient)
            pivot.components.set(ImageBasedLightReceiverComponent(imageBasedLight: ambient))
        }

        pivot.components.set(OpacityComponent(opacity: 0))
        subscription = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            guard let self else { return }
            let delta = Float(event.deltaTime)
            if isModelReady, !isDrawn {
                framesDrawn += 1
                if framesDrawn >= 8 { isDrawn = true }
            }
            if isRevealed, shown < 1, delta.isFinite {
                shown = min(shown + delta / 0.35, 1)
                pivot.components.set(OpacityComponent(opacity: shown))
            }
            if isRevealed, shown >= 1, !isDragging, delta.isFinite { angle += 0.4 * delta }
            pivot.orientation = .y(angle)
            if hop < 1, delta.isFinite {
                hop = min(hop + delta / 0.6, 1)
                pivot.position.y = 0.06 * sin(hop * .pi) * (1 - hop * 0.3)
            }
        }

        guard !isLoading, !isModelReady else { return }
        isLoading = true
        Task { await load(named: item.thumbnail) }
    }

    func scene(for item: ShopItem) -> AnyView { AnyView(ItemRealityPreview(item: item, turntable: self)) }

    func spin(_ delta: Float) {
        angle += delta
    }

    func celebrate() {
        hop = 0
    }

    private func load(named name: String) async {
        do {
            let model = try await Entity(named: name, in: .main)
            pivot.addChild(model)
            let bounds = model.visualBounds(relativeTo: pivot)
            frame(bounds)
            pivot.addChild(Self.makeShadow(under: bounds))
            if let light = pivot.components[ImageBasedLightReceiverComponent.self] {
                model.forEachDescendant { $0.components.set(light) }
            }

            // Ready only once the model is in the scene with its final transform; the update loop then counts
            // frames before the still may go.
            isModelReady = true
        } catch {
            print("\(name) failed to load: \(error)")
        }
    }

    /// The thumbnail's camera from Tools/make_items.py: a 70 mm lens on a 36 mm sensor, looking along (0.55, -1, 0.62)
    /// in Blender (the export mirrors x and turns z up into y), backed off until the bounds' sphere fits with 20% to
    /// spare. The stage is a little taller than the still, so the field of view widens by that much.
    private func frame(_ bounds: BoundingBox) {
        let half = atan(Float(18) / 70)
        let radius = simd_length(bounds.extents) / 2
        let direction = simd_normalize(SIMD3<Float>(-0.55, 0.62, 1))
        let distance = radius / sin(half) * 1.2
        let still = Self.stageHeight - 2 * Float(Self.thumbnailInset)
        camera.camera.fieldOfViewInDegrees = 2 * atan(tan(half) * Self.stageHeight / still) * 180 / .pi
        camera.look(at: bounds.center, from: bounds.center + direction * distance, relativeTo: nil)
    }

    private static func makeShadow(under bounds: BoundingBox) -> Entity {
        let side = max(bounds.extents.x, bounds.extents.z) * 1.5
        let size = CGSize(width: 128, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor.black.withAlphaComponent(0.4).cgColor, UIColor.black.withAlphaComponent(0).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                            locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                             endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
        var material = UnlitMaterial()
        if let cg = image.cgImage, let texture = try? TextureResource(image: cg, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        material.blending = .transparent(opacity: .init(floatLiteral: 1))
        let plane = ModelEntity(mesh: .generatePlane(width: side, depth: side), materials: [material])
        plane.position = [bounds.center.x, bounds.min.y + 0.001, bounds.center.z]
        return plane
    }

    /// The thumbnails' warm studio: the same tone as their world color.
    private static func makeAmbient() -> Entity? {
        guard let image = CatRoom.gradientImage(top: Daylight.rgb(0xFFF1E2), bottom: Daylight.rgb(0xE8C9A8)),
              let env = try? EnvironmentResource(equirectangular: image) else { return nil }
        let ambient = Entity()
        ambient.components.set(ImageBasedLightComponent(source: .single(env), intensityExponent: 0.2))
        return ambient
    }

    private static func makeSun() -> Entity {
        let sun = Entity()
        var directional = DirectionalLightComponent(color: UIColor(hex: 0xFFE2BC), intensity: 2500)
        directional.isRealWorldProxy = false
        sun.components.set(directional)

        var shadow = DirectionalLightComponent.Shadow()
        shadow.shadowProjection = .automatic(maximumDistance: 4)
        shadow.depthBias = 2
        sun.components.set(shadow)

        sun.look(at: [0, 0.25, 0], from: [1.4, 2.6, 1.6], relativeTo: nil)
        return sun
    }
}
