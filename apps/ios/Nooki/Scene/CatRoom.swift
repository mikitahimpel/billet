import Pet
import RealityKit
import SwiftUI

class CatRoom {
    /// With no `seconds` a step lasts until she stops moving.
    struct ShowcaseStep {
        let label: String
        let seconds: Float?
        let start: () -> Void
        var end: () -> Void = {}
    }

    let root = Entity()
    /// Rotated by the user's drag; everything visible hangs off it.
    let pivot = Entity()
    var onShowcase: ((String?) -> Void)?
    /// While set the room neither animates nor draws, though it stays attached to its view.
    var paused = false {
        didSet { root.isEnabled = !paused }
    }
    var isPlayingGame = false

    private(set) var catGroup = Entity()
    private var catBody = Entity()
    private var catModel = Entity()
    private(set) var walker: CatWalker?
    private(set) var director: CatDirector?
    /// The pair's journal once paired; `RoomController` connects it.
    static let catLife = CatLife()
    static let catAnalytics: CatAnalytics = NoCatAnalytics()
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
    var settledYaw: Float { yaw }
    /// Mochi's head in pivot space.
    var catFocus: SIMD3<Float> { catGroup.position + [0, catHeadTop * 0.55, 0] }
    var isShowcasing: Bool { !showcase.isEmpty }

    struct Framing {
        var target: SIMD3<Float> = [-0.02, 0.2, 0.02]
        var direction: SIMD3<Float> = simd_normalize(SIMD3<Float>(1, 0.82, 1))
        var far: Float = 7.0
        var near: Float = 2.6
    }
    var framing: Framing { Framing() }
    var yawLimit: Float { 0.75 }
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

    /// Nil for the whole room; `onFocusChange` hears every change.
    private(set) var focusedPhoto: Entity?
    var onFocusChange: ((Bool) -> Void)?
    private var focusedAt: Float = 0

    /// `photo` is a plane facing +z, centred on its origin.
    func focus(on photo: Entity) {
        focusedPhoto = photo
        focusedAt = time
        onFocusChange?(true)
    }

    /// Ignored right after focusing, so the double tap that focused doesn't also undo it.
    func unfocusPhoto() {
        guard focusedPhoto != nil, time - focusedAt > 0.4 else { return }
        focusedPhoto = nil
        onFocusChange?(false)
    }

    /// In world space.
    var photoPose: (center: SIMD3<Float>, normal: SIMD3<Float>)? {
        guard let photo = focusedPhoto else { return nil }
        return (photo.position(relativeTo: nil), simd_normalize(photo.convert(direction: [0, 0, 1], to: nil)))
    }

    func tapped(_ entity: Entity) {}
    func doubleTapped(_ entity: Entity) {}

    static func tappable(_ entity: Entity, size: SIMD3<Float>, at center: SIMD3<Float>) {
        entity.components.set(CollisionComponent(shapes: [.generateBox(size: size).offsetBy(translation: center)]))
        entity.components.set(InputTargetComponent())
    }

    func purr() {
        purrStart = time
        walker?.pet()
        director?.petted()
    }

    func appOpened() {
        director?.appOpened()
    }

    /// Besides her bed; a room with a route offers its far end.
    var catSpots: [NookiSpot: CatWalker.Destination] {
        walker?.main.map { [.tree: $0] } ?? [:]
    }

    /// A round obstacle her walks go around, in the pivot's floor plane.
    var catKeepOut: (center: SIMD2<Float>, radius: Float)? { nil }

    /// In the pivot's space, along the floor.
    private var cameraDirection: SIMD3<Float> {
        var d = simd_quatf.y(-yaw).act(framing.direction)
        d.y = 0
        return simd_normalize(d)
    }

    /// `offset` is points from her head on screen; nil stops her.
    func follow(_ offset: CGSize?) {
        walker?.follow(offset.map { SIMD2<Float>(Float($0.width), Float($0.height)) / 400 })
    }

    /// Hands the frame time to `beforeProjecting` first (the camera follows `settledYaw`), then reports where the
    /// spot above Mochi's head lands on screen. `viewer` is the camera.
    func start(updatesFrom content: RealityViewCameraContent, viewer: Entity, beforeProjecting: @escaping (Float) -> Void,
               onFrame: @escaping (CGPoint?) -> Void) {
        Self.shown = self
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

    /// Also ends any showcase.
    func stop() {
        if Self.shown === self { Self.shown = nil }
        subscription?.cancel()
        subscription = nil
        guard let step = showcase.first else { return }
        step.end()
        showcase = []
        walker?.wandering = wandered
        onShowcase?(nil)
    }

    /// Rooms add their own motion after calling this.
    func tick(_ dt: Float) {
        time += dt
        frame += 1
        let t = time

        yaw += (targetYaw - yaw) * min(1, dt * 8)
        pivot.orientation = .y(yaw + 0.035 * sin(t * 0.35))

        director?.paused = isShowcasing || isPlayingGame
        director?.update(dt)
        walker?.update(dt)

        // A quick squash-and-stretch after a tap while her mesh is still loading; posed, she leans into the pet
        // instead, and breathes on her own skeleton.
        let p = t - purrStart
        let bounce: Float = p < 0.7 && walker?.standing.entity == nil ? sin(p / 0.7 * .pi * 3) * (1 - p / 0.7) * 0.12 : 0
        catBody.scale = [1 + 0.4 * bounce, 1 - bounce, 1 + 0.4 * bounce]

        advanceShowcase(dt)
    }

    // MARK: - Mochi

    /// Mochi sitting at `at` facing `rests.last`; with a route she walks between its ends, `rests` her yaws at each.
    /// Splats where the GPU draws them, else meshes of the same splats (Cat.usdz, CatStanding.usdz); loaded once in
    /// the background and shared by the rooms (see `adoptCat`).
    func buildCat(at: SIMD3<Float>, rests: [Float], route: [CatWalker.Waypoint] = [], scale: Float, wandering: Bool) {
        Task {
            let mochi: Mochi
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

            let walker = CatWalker(group: catGroup, standing: mochi.standing, seated: mochi.seated, bodies: Self.bodies,
                                   scale: scale, rests: rests, route: route, wandering: wandering)
            walker.keepOut = catKeepOut
            walker.needsBody = { Self.needBody($0) }
            Self.rooms.add(self)
            self.walker = walker
            director = CatDirector(walker: walker, spots: catSpots, source: Self.catLife, analytics: Self.catAnalytics,
                                   cameraDirection: { [unowned self] in cameraDirection })
            director?.appOpened()
            catHeadTop = 0.3 * scale
            if subscription != nil { adoptCat() }
            OurioPerf.catPlaced()
        }
    }

    /// Reloads her for the next room built, after her coat changed.
    static func forgetMochi() {
        mochi = nil
        for load in bodyLoads.values { load.cancel() }
        bodyLoads = [:]
        bodies = [:]
        rooms.removeAllObjects()
    }

    private struct Mochi {
        let standing: CatRig
        let seated: CatRig
    }

    /// Her lying bodies where splats are drawn (the meshes have none), shared by every room's walker like her other
    /// rigs, loaded with her and kept. Without one she lies down on the standing splat with its legs folded under
    /// her, which looks wrong, so `needBody` only stands in when one failed to load at launch.
    private static var bodies: [NookiRestPose: CatRig] = [:]
    private static var bodyLoads: [NookiRestPose: Task<Void, Never>] = [:]
    private static let bodyFiles: [NookiRestPose: String] = [.loaf: "MochiLoaf", .sleep: "MochiSleep"]
    /// Rooms with a walker, and the one on screen, which holds her entities.
    private static let rooms = NSHashTable<CatRoom>.weakObjects()
    private static weak var shown: CatRoom?
    private static var catShadows = true

    private static func needBody(_ pose: NookiRestPose) {
        guard SplatLoader.isSupported, bodies[pose] == nil, bodyLoads[pose] == nil, let name = bodyFiles[pose] else { return }
        bodyLoads[pose] = Task {
            // A failed load stays in `bodyLoads`, so she lies on the standing splat instead of retrying every rest.
            do {
                let file = try await Task.detached {
                    try CatRig.Files(named: name, drawn: true, in: CatCoat.current().bundle(poses: [name]))
                }.value
                guard !Task.isCancelled else { return }
                let rig = try CatRig(file)
                if let entity = rig.entity {
                    entity.isEnabled = false
                    castShadow(entity, catShadows)
                }
                bodies[pose] = rig
                bodyLoads[pose] = nil
                for room in rooms.allObjects { room.walker?.setBody(pose, rig) }
                shown?.adoptCat()
            } catch {
                print("\(name) failed to load: \(error)")
            }
        }
    }

    private static func castShadow(_ entity: Entity, _ isOn: Bool = true) {
        entity.components.set(GroundingShadowComponent(castsShadow: isOn))
        entity.forEachDescendant { $0.components.set(GroundingShadowComponent(castsShadow: isOn)) }
    }

    /// For a perf run's `cost` step.
    func setCatShadow(_ isOn: Bool) {
        Self.catShadows = isOn
        guard let walker else { return }
        for entity in ([walker.standing, walker.seated] + walker.bodies.values).compactMap(\.entity) {
            Self.castShadow(entity, isOn)
        }
    }

    private static var mochi: Task<Mochi, any Error>?

    private static func loadMochi() async throws -> Mochi {
        if let mochi { return try await mochi.value }
        let task = Task {
            let drawn = SplatLoader.isSupported
            let files = try await Task.detached {
                // Grey reads the original files from the app; another coat reads its recoloured copy (CatCoat.bundle).
                let coat = try drawn ? CatCoat.current().bundle(poses: ["MochiStanding", "Mochi"]) : .main
                return (try CatRig.Files(named: "MochiStanding", drawn: drawn, in: coat),
                        try CatRig.Files(named: "Mochi", drawn: drawn, in: coat))
            }.value
            let standing = try CatRig(files.0), seated = try CatRig(files.1)
            if !drawn {
                for (rig, file) in [(seated, "Cat"), (standing, "CatStanding")] {
                    do {
                        let model = try await Entity(named: file, in: .main)
                        await CatCoat.current().dress(model, model: file)
                        try rig.wear(model)
                    } catch {
                        print("\(file) failed to load: \(error)")
                    }
                }
            }
            for entity in [standing.entity, seated.entity].compactMap({ $0 }) { castShadow(entity) }
            // Her loaf and sleep come with her, so she never lies down before her lying body is there.
            if drawn {
                for (pose, name) in bodyFiles where bodies[pose] == nil {
                    do {
                        let file = try await Task.detached {
                            try CatRig.Files(named: name, drawn: true, in: CatCoat.current().bundle(poses: [name]))
                        }.value
                        let rig = try CatRig(file)
                        if let entity = rig.entity {
                            entity.isEnabled = false
                            castShadow(entity, catShadows)
                        }
                        bodies[pose] = rig
                    } catch {
                        print("\(name) failed to load: \(error)")
                    }
                }
            }
            return Mochi(standing: standing, seated: seated)
        }
        mochi = task
        return try await task.value
    }

    /// Lit by this room's ambient light and posed as this room's walker last left her.
    func adoptCat() {
        guard let walker else { return }
        for rig in [walker.standing, walker.seated] + walker.bodies.values {
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

    /// Bloom is iOS 27 only. The threshold sits above the lit walls so only emissive bulbs, flame and window halo
    /// glow. The compiler check lets Xcode 26 (the perf runs' image), whose SDK has no bloom, build the app.
    func addBloom() {
        #if compiler(>=6.4)
        guard #available(iOS 27, *) else { return }
        var bloom = BloomOptionsComponent()
        bloom.strength = 0.35
        bloom.threshold = 1.1
        root.components.set(BloomComponent(scope: .unbounded))
        root.components.set(bloom)
        #endif
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

    /// Played before Mochi's trip.
    var roomShowcase: [ShowcaseStep] { [] }

    /// Each animation once, then her walk and jumps there and back.
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
