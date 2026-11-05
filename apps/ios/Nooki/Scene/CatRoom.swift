import RealityKit
import SwiftUI

/// What every room shares, ported from nooki-scene/src/three/catRoom.js: the turning pivot, Mochi on her two
/// skeletons with a pet bounce, and a showcase that plays each of her animations in turn.
class CatRoom {
    /// One step of the showcase: `label` shows while it runs, `start` kicks it off; with no `seconds` it lasts until
    /// she stops moving.
    struct ShowcaseStep {
        let label: String
        let seconds: Float?
        let start: () -> Void
        var end: () -> Void = {}
    }

    let root = Entity()
    /// Rotated by the user's drag; everything visible hangs off it.
    let pivot = Entity()
    /// Called with the showcase step's label as it changes, nil once it is over.
    var onShowcase: ((String?) -> Void)?
    /// While set the room neither animates nor draws, though it stays attached to its view.
    var paused = false {
        didSet { root.isEnabled = !paused }
    }

    private(set) var catGroup = Entity()
    private var catBody = Entity()
    private var catModel = Entity()
    private(set) var walker: CatWalker?
    /// Height above the cat's origin where the speech bubble anchors.
    private var catHeadTop: Float = 0.12
    var iblReceiver: ImageBasedLightReceiverComponent?

    private(set) var time: Float = 0
    private(set) var frame = 0
    private var yaw: Float = 0
    private var targetYaw: Float = 0
    private var purrStart: Float = -10
    private var subscription: EventSubscription?
    private var showcase: [ShowcaseStep] = []
    private var showcaseTime: Float = 0
    private var wandered = false

    init() {
        root.addChild(pivot)
    }

    // MARK: - Interaction

    var currentYaw: Float { targetYaw }
    /// Eased rotation actually applied to the pivot this frame.
    var settledYaw: Float { yaw }
    /// Mochi's head in pivot space, for the camera's close-up.
    var catFocus: SIMD3<Float> { catGroup.position + [0, catHeadTop * 0.55, 0] }
    var isShowcasing: Bool { !showcase.isEmpty }

    /// How the camera frames the room: what it looks at, from which direction, and how far away at zoom 0 and 1.
    struct Framing {
        var target: SIMD3<Float> = [-0.02, 0.2, 0.02]
        var direction: SIMD3<Float> = simd_normalize(SIMD3<Float>(1, 0.82, 1))
        var far: Float = 7.0
        var near: Float = 2.6
    }
    var framing: Framing { Framing() }
    /// How far a drag may turn the room either way.
    var yawLimit: Float { 0.75 }
    /// How far in front of a focused photo the camera stops.
    var focusDistance: Float { 0.8 }

    func setYaw(_ value: Float) {
        targetYaw = min(max(value, -yawLimit), yawLimit)
    }

    func isCat(_ entity: Entity) -> Bool {
        var node: Entity? = entity
        while let n = node {
            if n === catGroup { return true }
            node = n.parent
        }
        return false
    }

    /// The photo the camera is looking at up close, nil for the whole room; `onFocusChange` hears every change.
    private(set) var focusedPhoto: Entity?
    var onFocusChange: ((Bool) -> Void)?
    private var focusedAt: Float = 0

    /// Brings the camera up to `photo`, a plane facing +z with its center at its origin.
    func focus(on photo: Entity) {
        focusedPhoto = photo
        focusedAt = time
        onFocusChange?(true)
    }

    /// Back to the whole room. Ignored right after focusing, so the double tap that focused doesn't also undo it.
    func unfocusPhoto() {
        guard focusedPhoto != nil, time - focusedAt > 0.4 else { return }
        focusedPhoto = nil
        onFocusChange?(false)
    }

    /// The focused photo's center and facing in world space, for the camera.
    var photoPose: (center: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard let photo = focusedPhoto else { return nil }
        return (photo.position(relativeTo: nil), simd_normalize(photo.convert(direction: [0, 0, 1], to: nil)))
    }

    /// A tap on something in the room other than Mochi; rooms send her to their toys and furniture.
    func tapped(_ entity: Entity) {}
    /// A double tap on something in the room.
    func doubleTapped(_ entity: Entity) {}

    /// Makes `entity` and everything under it answer taps.
    static func tappable(_ entity: Entity, size: SIMD3<Float>, at center: SIMD3<Float>) {
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
        entity.components.set(InputTargetComponent())
    }

    func purr() {
        purrStart = time
        walker?.pet()
    }

    /// Makes Mochi follow a finger dragged `offset` points from her head on screen, or stop with nil.
    func follow(_ offset: CGSize?) {
        walker?.follow(offset.map { SIMD2<Float>(Float($0.width), Float($0.height)) / 400 })
    }

    /// Drives animation every frame, hands the frame time on to `beforeProjecting` first (the camera follows
    /// `settledYaw`), and reports where the spot above Mochi's head lands on screen.
    /// `viewer` is the camera, which Mochi checks on now and then.
    func start(updatesFrom content: RealityViewCameraContent, viewer: Entity, beforeProjecting: @escaping (Float) -> Void,
               onFrame: @escaping (CGPoint?) -> Void) {
        adoptCat()
        subscription = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) { [weak self] event in
            guard let self, !paused else { return }
            let dt = Float(event.deltaTime)
            walker?.watch(catModel.convert(position: viewer.position(relativeTo: nil), from: nil))
            tick(dt)
            beforeProjecting(dt)
            let anchor = catGroup.position(relativeTo: nil) + [0, catHeadTop, 0]
            onFrame(walker == nil ? nil : content.project(point: anchor, to: .local))
        }
    }

    /// Stops driving the room while another one is shown, ending any showcase.
    func stop() {
        subscription?.cancel()
        subscription = nil
        guard let step = showcase.first else { return }
        step.end()
        showcase = []
        walker?.wandering = wandered
        onShowcase?(nil)
    }

    /// Advances the clock, the room's idle sway and Mochi; rooms add their own motion after calling this.
    func tick(_ dt: Float) {
        time += dt
        frame += 1
        let t = time

        // Drag follows with easing, plus a slow idle sway.
        yaw += (targetYaw - yaw) * min(1, dt * 8)
        pivot.orientation = .y(yaw + 0.035 * sin(t * 0.35))

        walker?.update(dt)

        // A quick squash-and-stretch after a tap while her mesh is still loading; posed, she leans into the pet
        // instead, and breathes on her own skeleton.
        let p = t - purrStart
        let bounce: Float = p < 0.7 && walker?.standing.entity == nil ? sin(p / 0.7 * .pi * 3) * (1 - p / 0.7) * 0.12 : 0
        catBody.scale = [1 + 0.4 * bounce, 1 - bounce, 1 + 0.4 * bounce]

        advanceShowcase(dt)
    }

    // MARK: - Mochi

    /// Mochi sitting at `at` (where her seated splat stands) facing `rests.last`; with a route she can walk between
    /// its two ends (see CatWalker), `rests` being her yaws at its start and end. Where the GPU can draw splats she is
    /// the two Gaussian splats on their skeletons, otherwise meshes of the same two splats on the same skeletons
    /// (Cat.usdz, CatStanding.usdz). Both are loaded once in the background and shared by the rooms (see `adoptCat`).
    func buildCat(at: SIMD3<Float>, rests: [Float], route: [CatWalker.Waypoint] = [], scale: Float, wandering: Bool) {
        Task {
            let mochi: (standing: CatRig, seated: CatRig)
            do {
                mochi = try await Self.loadMochi()
            } catch {
                print("Cat rig failed to load: \(error)")
                return
            }
            // The group stands at the standing splat's origin; the seated one sits `mount` from it.
            let origin = route.last?.at ?? at - simd_quatf.y(rests[rests.count - 1]).act(mochi.seated.mount * scale)
            catGroup = pivot.group(at: origin)
            catBody = catGroup.group()
            catModel = catBody.group()
            catModel.scale = .init(repeating: scale)

            // One generous hit box over the cat is easier to tap than her exact shape.
            catGroup.components.set(CollisionComponent(shapes: [
                .generateBox(size: [0.3, 0.24, 0.3]).offsetBy(translation: [0, 0.065, 0])
            ]))
            catGroup.components.set(InputTargetComponent())

            walker = CatWalker(group: catGroup, standing: mochi.standing, seated: mochi.seated, scale: scale,
                               rests: rests, route: route, wandering: wandering)
            catHeadTop = 0.3 * scale
            if subscription != nil { adoptCat() }
        }
    }

    /// Mochi's two rigs, shared by every room.
    private static var mochi: Task<(standing: CatRig, seated: CatRig), any Error>?

    /// Puts Mochi in the chosen coat in every room, once she is loaded.
    static func wearChosenCoat() {
        Task {
            guard let mochi = try? await mochi?.value else { return }
            // Read after the wait: taps resume in no set order, and the last choice must win.
            for rig in [mochi.standing, mochi.seated] { rig.wear(coat: CatCoat.current.file) }
        }
    }

    private static func loadMochi() async throws -> (standing: CatRig, seated: CatRig) {
        if let mochi { return try await mochi.value }
        let task = Task {
            let drawn = SplatLoader.isSupported
            let files = try await Task.detached {
                (try CatRig.Files(named: "MochiStanding", drawn: drawn), try CatRig.Files(named: "Mochi", drawn: drawn))
            }.value
            let standing = try CatRig(files.0), seated = try CatRig(files.1)
            for rig in [standing, seated] { rig.wear(coat: CatCoat.current.file) }
            if !drawn {
                for (rig, file) in [(seated, "Cat"), (standing, "CatStanding")] {
                    do {
                        try rig.wear(try await Entity(named: file, in: .main))
                    } catch {
                        print("\(file) failed to load: \(error)")
                    }
                }
            }
            for entity in [standing.entity, seated.entity].compactMap({ $0 }) {
                entity.components.set(GroundingShadowComponent(castsShadow: true))
                entity.forEachDescendant { $0.components.set(GroundingShadowComponent(castsShadow: true)) }
            }
            return (standing: standing, seated: seated)
        }
        mochi = task
        return try await task.value
    }

    /// Moves Mochi into this room, lit by its ambient light and posed as this room's walker last left her.
    private func adoptCat() {
        guard let walker else { return }
        for rig in [walker.standing, walker.seated] {
            guard let entity = rig.entity, entity.parent !== catModel else { continue }
            catModel.addChild(entity)
            if let iblReceiver {
                entity.components.set(iblReceiver)
                entity.forEachDescendant { $0.components.set(iblReceiver) }
            }
        }
        walker.show()
    }

    /// Warm dust motes rising through a 1.3 x 0.9 x 1.3 box.
    func buildMotes() {
        let emitter = pivot.group(at: [0, 0.45, 0])
        var p = ParticleEmitterComponent()
        p.emitterShape = .box
        p.emitterShapeSize = [1.3, 0.9, 1.3]
        p.birthLocation = .volume
        p.speed = 0.01
        p.mainEmitter.birthRate = 14
        p.mainEmitter.lifeSpan = 5
        p.mainEmitter.size = 0.007
        p.mainEmitter.color = .constant(.single(UIColor(hex: 0xFFD58A)))
        p.mainEmitter.blendMode = .additive
        p.mainEmitter.opacityCurve = .gradualFadeInOut
        p.mainEmitter.acceleration = [0, 0.004, 0]
        p.mainEmitter.isLightingEnabled = false
        emitter.components.set(p)
    }

    // MARK: - Lighting

    /// Lights everything built so far with `ibl`; parts added later set `iblReceiver` on themselves.
    func receiveAmbient(from ibl: Entity) {
        root.addChild(ibl)
        let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ibl)
        iblReceiver = receiver
        pivot.forEachDescendant { $0.components.set(receiver) }
    }

    static func castShadow(_ sun: Entity) {
        var shadow = DirectionalLightComponent.Shadow()
        shadow.shadowProjection = .automatic(maximumDistance: 4)
        shadow.depthBias = 2
        sun.components.set(shadow)
    }

    /// Bloom is iOS 27 only; earlier systems get the room without the glow. The threshold sits above the lit walls
    /// so only the emissive bulbs, flame and window halo glow, not the whole room.
    func addBloom() {
        guard #available(iOS 27, *) else { return }
        var bloom = BloomOptionsComponent()
        bloom.strength = 0.35
        bloom.threshold = 1.1
        root.components.set(BloomComponent(scope: .unbounded))
        root.components.set(bloom)
    }

    /// A 64 x 32 vertical gradient for a room's ambient environment.
    static func gradientImage(top: SIMD3<Float>, bottom: SIMD3<Float>) -> CGImage? {
        let size = CGSize(width: 64, height: 32)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [Daylight.color(top).cgColor, Daylight.color(bottom).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }.cgImage
    }

    // MARK: - Showcase

    /// Extra steps a room adds to the showcase, played before Mochi's trip.
    var roomShowcase: [ShowcaseStep] { [] }

    /// Plays each of Mochi's animations once, one after another, then her walk and jumps there and back.
    func playAll() {
        guard let walker, !isShowcasing else { return }
        let b = walker.behavior
        var steps: [ShowcaseStep] = [
            .init(label: "Purr", seconds: 2.6) { [unowned self] in purr() },
            .init(label: "Ear twitch", seconds: 1.4) { b.perform(.twitch) },
            .init(label: "Listening", seconds: 2.8) { b.perform(.listen) },
            .init(label: "Slow blink", seconds: 2.4) { b.perform(.slowBlink) },
            .init(label: "Yawn", seconds: 3.2) { b.perform(.yawn) },
            .init(label: "Tail flick", seconds: 1.6) { b.perform(.flick) },
            .init(label: "Tail curl", seconds: 3.4) { b.perform(.curl) },
            .init(label: "Washing", seconds: 5.4) { b.perform(.groom) },
            .init(label: "Falling asleep", seconds: 7) { b.perform(.doze(7)) },
        ]
        steps += roomShowcase
        if walker.canTrip {
            steps.append(.init(label: "Stretch, walk and jump", seconds: nil) { walker.trip(stretch: true) })
            steps.append(.init(label: "And back", seconds: nil) { walker.trip() })
        }
        wandered = walker.wandering
        walker.wandering = false
        showcase = steps
        showcaseTime = 0
        steps[0].start()
        onShowcase?(steps[0].label)
    }

    private func advanceShowcase(_ dt: Float) {
        guard let step = showcase.first, let walker else { return }
        showcaseTime += dt
        let done = step.seconds.map { showcaseTime >= $0 } ?? (showcaseTime > 0.3 && !walker.moving)
        guard done else { return }
        step.end()
        showcase.removeFirst()
        showcaseTime = 0
        if let next = showcase.first {
            next.start()
            onShowcase?(next.label)
        } else {
            walker.wandering = wandered
            onShowcase?(nil)
        }
    }
}
