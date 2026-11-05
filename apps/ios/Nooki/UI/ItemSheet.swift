import Observation
import RealityKit
import SwiftUI
import UIKit

// MARK: - Item sheet

struct ItemSheet: View {
    let item: ShopItem
    let state: HomeState

    @Environment(\.dismiss) private var dismiss

    @State private var turntable = ItemTurntable()
    /// Still frame stays up until the 3D preview has really had a chance to draw.
    @State private var showsPlaceholder = true
    @State private var celebrating = false


    private var cost: Int { state.shop.price(of: item) }
    private var affordable: Bool { state.shop.coins >= cost }
    private var owned: Bool { state.shop.owned.contains(item.id) }
    private var isDeal: Bool { cost < item.price }


    var body: some View {
        VStack(spacing: 0) {
            scene
                .padding(.horizontal, 20)
                .padding(.top, 6)

            Spacer(minLength: 8)

            details
                .padding(.horizontal, 20)

            Spacer(minLength: 8)

            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .usSheet(detents: [.fraction(0.68)])
    }

    // MARK: 3D scene

    private var scene: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0xF4BF7E).opacity(0.6),
                                              Color(hex: 0xB36E3A).opacity(0.32),
                                              Color(hex: 0x2A1A12).opacity(0.05)],
                                     center: UnitPoint(x: 0.5, y: 0.46),
                                     startRadius: 6, endRadius: 230))

            // The model's camera matches the thumbnail's (see ItemTurntable.frame), so the still
            // dissolves into the live model without the two ever showing side by side.
            // Always on screen, so RealityKit is already drawing; the model inside stays hidden
            // until the turntable fades it in (see ItemTurntable.isRevealed).
            ItemRealityPreview(item: item, turntable: turntable)

            // Static thumbnail stands in for the model until the 3D preview is actually drawn.
            if let image = Thumbnails.image(item.thumbnail, maxPixels: 900) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, ItemTurntable.thumbnailInset)
                    .opacity(showsPlaceholder ? 1 : 0)
                    .allowsHitTesting(false)
            }

            // Horizontal drags spin the model; vertical ones are left to the sheet's own pan.
            HorizontalDragCatcher(
                onBegan: {
                    turntable.isDragging = true
                    reveal()
                },
                onChanged: { dx in turntable.spin(Float(dx) * 0.012) },
                onEnded: { turntable.isDragging = false }
            )

            closeButton
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 32))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .scaleEffect(celebrating ? 1.03 : 1)
    }

    private func reveal() {
        // note: the still stays until the first drag, because the simulator puts RealityKit frames on screen
        // late and an automatic swap showed an empty stage; bring back a timed swap once checked on a device.
        guard showsPlaceholder, turntable.isDrawn else { return }
        // The model fades in under the still first, so lifting the still never uncovers an empty stage.
        turntable.isRevealed = true
        withAnimation(.easeInOut(duration: 0.3).delay(0.5)) { showsPlaceholder = false }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Ink.primary)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.22), in: .circle)
        }
        .buttonStyle(.plain)
        .glass(.circle, interactive: true)
        .accessibilityLabel("Close")
    }

    // MARK: Details

    private var details: some View {
        VStack(spacing: 8) {
            Text(item.name)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.primary)
                .multilineTextAlignment(.center)

            Text(item.blurb)
                .font(.system(size: 15))
                .foregroundStyle(Ink.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        VStack(spacing: 10) {
            if owned {
                Label("Yours", systemImage: "checkmark")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xFFD9A8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(.white.opacity(0.08), in: .capsule)
            } else {
                Button(action: buy) { buyLabel.frame(maxWidth: .infinity) }
                    .nookiPrimary()
                    .disabled(!affordable)

                if !affordable {
                    Text("Earn coins by answering today's question")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: owned)
    }

    private var buyLabel: some View {
        HStack(spacing: 8) {
            if affordable {
                Text("Buy for")
                CoinIcon(size: 22)
                Text("\(cost)")
                    .monospacedDigit()
                if isDeal {
                    Text("\(item.price)")
                        .font(.nookiCaption.monospacedDigit())
                        .strikethrough()
                        .opacity(0.7)
                        .accessibilityLabel("was \(item.price)")
                }
            } else {
                Image(systemName: "lock.fill")
                Text("Need \(cost - state.shop.coins) more")
                    .monospacedDigit()
            }
        }
    }

    private func buy() {
        guard state.shop.buy(item) else { return }
        turntable.celebrate()
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) { celebrating = true }
        withAnimation(.spring(duration: 0.4).delay(0.3)) { celebrating = false }
        // The purchase moment plays over the app once the sheet is out of the way.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            dismiss()
        }
    }
}

// MARK: - 3D preview

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

/// Horizontal-only pan: vertical drags are declined by the recognizer so the sheet keeps its
/// own pull-to-dismiss behaviour.
private struct HorizontalDragCatcher: UIViewRepresentable {
    var onBegan: () -> Void
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: () -> Void
        var onChanged: (CGFloat) -> Void
        var onEnded: () -> Void

        private var lastX: CGFloat = 0

        init(onBegan: @escaping () -> Void, onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        /// Only claim drags that are clearly horizontal; everything else belongs to the sheet.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func handle(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                lastX = 0
                onBegan()
            case .changed:
                let x = pan.translation(in: pan.view).x
                onChanged(x - lastX)
                lastX = x
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }
    }
}

/// Owns the entity graph for one sheet: frames the model the way its thumbnail is framed, spins it, and follows drags.
@Observable
private final class ItemTurntable {
    /// True once the scene has drawn a few frames with the model loaded (hidden), so the still can give way to it.
    var isDrawn = false
    /// Set as the still fades: the model fades in over it, and only starts turning once it has.
    @ObservationIgnored var isRevealed = false
    @ObservationIgnored private var isModelReady = false
    @ObservationIgnored private var framesDrawn = 0
    @ObservationIgnored private var shown: Float = 0

    /// Vertical padding the still gets inside the 300 pt stage; the camera allows for it.
    static let thumbnailInset: CGFloat = 8
    private static let stageHeight: Float = 300

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
            // A little hop when it is bought.
            if hop < 1, delta.isFinite {
                hop = min(hop + delta / 0.6, 1)
                pivot.position.y = 0.06 * sin(hop * .pi) * (1 - hop * 0.3)
            }
        }

        guard !isLoading, !isModelReady else { return }
        isLoading = true
        Task { await load(named: item.thumbnail) }
    }

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

    /// The thumbnail's camera from Tools/make_items.py: a 70 mm lens on a 36 mm sensor, looking along
    /// (0.55, -1, 0.62) in Blender (the export mirrors x and turns z up into y), backed off until the bounds' sphere fits
    /// with 20% to spare. The stage is a little taller than the still, so the field of view widens by that much.
    private func frame(_ bounds: BoundingBox) {
        let half = atan(Float(18) / 70)
        let radius = simd_length(bounds.extents) / 2
        let direction = simd_normalize(SIMD3<Float>(-0.55, 0.62, 1))
        let distance = radius / sin(half) * 1.2
        let still = Self.stageHeight - 2 * Float(Self.thumbnailInset)
        camera.camera.fieldOfViewInDegrees = 2 * atan(tan(half) * Self.stageHeight / still) * 180 / .pi
        camera.look(at: bounds.center, from: bounds.center + direction * distance, relativeTo: nil)
    }

    /// A soft round contact shadow on the floor under the model.
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
