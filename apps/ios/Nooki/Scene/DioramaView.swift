import RealityKit
import RoomInterface
import SwiftUI

struct DioramaView: View {
    let scene: CatRoom
    /// Off-screen, the room stops animating and drawing.
    let paused: Bool
    let petPulse: Int
    /// False while the pieces are arranged: the heart bubble would hide what is being moved.
    var showsBubble = true
    let rendering: RoomRendering
    /// Draws the room with its own renderer and frame loop in place of a `RealityView`, when there is one.
    var loop: RoomRenderLoop?
    var onPet: () -> Void
    /// A finger came down on the room (true) or lifted from it; the quality governor reads it.
    var onTouch: (Bool) -> Void = { _ in }

    @State private var rig = ZoomRig()
    @State private var dragStartYaw: Float?
    @State private var pinchStartZoom: Float?
    @State private var bubble = BubbleSpot()
    @State private var photoFocused = false

    /// Shows `scene` in place of any other room and drives it from this view's frames.
    private func attach(_ scene: CatRoom, to content: RealityViewCameraContent) {
        for entity in Array(content.entities) where entity !== rig.camera { content.remove(entity) }
        content.add(scene.root)
        drive(scene, on: content, rig: rig)
    }

    private func attach(_ scene: CatRoom, to loop: RoomRenderLoop) {
        loop.show(scene)
        drive(scene, on: loop, rig: loop.rig)
    }

    private func drive(_ scene: CatRoom, on surface: any RoomSurface, rig: ZoomRig) {
        scene.paused = paused
        scene.unprojector = { point, plane in surface.unproject(point, ontoPlane: plane) }
        scene.onFocusChange = { focused in withAnimation(.easeOut(duration: 0.3)) { photoFocused = focused } }
        let bubble = bubble
        scene.start(on: surface, viewer: rig.camera, beforeProjecting: { dt in
            rig.update(dt: dt, framing: scene.framing, focusDistance: scene.focusDistance,
                       yaw: scene.settledYaw, focus: scene.catFocus, photo: scene.photoPose, adjust: scene.cameraAdjust)
        }) { projected in
            guard let projected else { return }
            if let old = bubble.point, hypot(old.x - projected.x, old.y - projected.y) < 2 { return }
            bubble.point = projected
        }
    }

    private func tapped(_ entity: Entity) {
        if scene.focusedPhoto != nil { return scene.unfocusPhoto() }
        // HomeView plays the purr when the pet lands, the same way for taps and widget pets.
        guard scene.isCat(entity) else { return scene.tapped(entity) }
        onPet()
    }

    private func doubleTapped(_ entity: Entity) {
        if scene.focusedPhoto != nil { return scene.unfocusPhoto() }
        scene.doubleTapped(entity)
    }

    @ViewBuilder private var canvas: some View {
        if let loop {
            RoomCanvas(loop: loop)
                .onChange(of: ObjectIdentifier(scene), initial: true) { attach(scene, to: loop) }
                .onChange(of: rendering.antialiasing, initial: true) { loop.setAntialiasing(rendering.antialiasing) }
                .onChange(of: rendering, initial: true) { loop.setQuality(rendering) }
                // A room that stopped while covered or hidden is the same scene when it comes back, so this is where
                // it starts again.
                .onChange(of: paused, initial: true) {
                    loop.setRunning(!paused)
                    if !paused { attach(scene, to: loop) }
                }
        } else {
            RealityView { content in
                content.camera = .virtual
                apply(rendering, to: &content)
                content.add(rig.camera)
                attach(scene, to: content)
            } update: { content in
                apply(rendering, to: &content)
                // A new room swaps its root into this same view, so there is never a second renderer running.
                if !content.entities.contains(where: { $0 === scene.root }) { attach(scene, to: content) }
            }
        }
    }

    /// The camera's own effects: the room has no use for blur, depth of field or grain, and each costs a pass.
    private func apply(_ rendering: RoomRendering, to content: inout RealityViewCameraContent) {
        content.renderingEffects.motionBlur = .disabled
        content.renderingEffects.depthOfField = .disabled
        content.renderingEffects.cameraGrain = .disabled
        content.renderingEffects.antialiasing = rendering.antialiasing ? .multisample4X : .none
        content.renderingEffects.dynamicRange = rendering.hdr ? .default : .standard
    }

    var body: some View {
        canvas
        .onGeometryChange(for: Float.self) { Float($0.size.width / max($0.size.height, 1)) } action: { aspect in
            rig.aspect = aspect
            loop?.rig.aspect = aspect
        }
        .overlay { BubbleOverlay(spot: bubble, pulse: petPulse).opacity(photoFocused || !showsBubble ? 0 : 1) }
        .overlay(alignment: .bottom) {
            if photoFocused {
                Button { scene.unfocusPhoto() } label: {
                    Label("Back to the room", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .glass(.capsule, interactive: true)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 150)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .onChange(of: paused) {
            scene.paused = paused
            // Out of the hierarchy, its endless float stops being animated behind a room nobody sees.
            if paused { bubble.point = nil }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in tapped(value.entity) },
            including: loop == nil ? .all : .none
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .targetedToAnyEntity()
                .onEnded { value in doubleTapped(value.entity) },
            including: loop == nil ? .all : .none
        )
        // With no view to hit-test, the same taps are found with a ray from the camera.
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let loop, let entity = scene.target(at: value.location, camera: loop.camera) { tapped(entity) }
            },
            including: loop == nil ? .none : .all
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                if let loop, let entity = scene.target(at: value.location, camera: loop.camera) { doubleTapped(entity) }
            },
            including: loop == nil ? .none : .all
        )
        // Taps on empty space, which the entity-targeted gestures never see, also leave a photo.
        .simultaneousGesture(SpatialTapGesture().onEnded { _ in
            onTouch(true)
            onTouch(false)
            scene.unfocusPhoto()
        })
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if dragStartYaw == nil { onTouch(true) }
                    let start = dragStartYaw ?? scene.currentYaw
                    dragStartYaw = start
                    scene.setYaw(start + Float(value.translation.width) * 0.006)
                    // She watches the finger, measured from her head where the bubble sits.
                    if let head = bubble.point {
                        scene.follow(CGSize(width: value.location.x - head.x, height: value.location.y - head.y))
                    }
                }
                .onEnded { _ in
                    dragStartYaw = nil
                    onTouch(false)
                    scene.follow(nil)
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard !photoFocused else { return }
                    if pinchStartZoom == nil { onTouch(true) }
                    let start = pinchStartZoom ?? rig.targetZoom
                    pinchStartZoom = start
                    let delta = Float(log2(Double(value.magnification))) * 0.6
                    rig.targetZoom = min(max(start + delta, 0), 1)
                }
                .onEnded { _ in
                    pinchStartZoom = nil
                    onTouch(false)
                }
        )
    }
}

/// Screen point just above Mochi, refreshed every frame so the bubble follows rotation. Only the overlay reads it,
/// so the frames re-render the bubble and not the room's view.
@Observable
private final class BubbleSpot {
    var point: CGPoint?
}

private struct BubbleOverlay: View {
    let spot: BubbleSpot
    let pulse: Int

    var body: some View {
        if let point = spot.point {
            HeartBubble(pulse: pulse)
                .position(x: point.x, y: point.y - 30)
                .allowsHitTesting(false)
        }
    }
}

/// Holds the single camera entity and eases its pose toward the requested zoom every frame.
@MainActor
final class ZoomRig {
    let camera = PerspectiveCamera()
    var targetZoom: Float = 0.25
    private var zoom: Float = 0.25

    /// Width over height of the view the camera draws into; the field of view follows it (`RoomFit`).
    var aspect: Float = RoomFit.referenceAspect {
        didSet {
            guard aspect != oldValue else { return }
            camera.camera.fieldOfViewInDegrees = RoomFit.verticalFieldOfView(Self.baseFieldOfView, aspect: aspect)
        }
    }
    private static let baseFieldOfView: Float = 22

    private var framing = CatRoom.Framing()
    private var focusDistance: Float = 0.8
    private var photo: Float = 0
    private var photoPose: (center: SIMD3<Float>, normal: SIMD3<Float>)?
    private var placed: (target: SIMD3<Float>, eye: SIMD3<Float>)?

    init() {
        camera.camera.fieldOfViewInDegrees = Self.baseFieldOfView
        apply(zoom: zoom, yaw: 0, focus: [0.06, 0.12, -0.04])
    }

    /// `framing` and `focusDistance` come from the room, `focus` is Mochi's head in pivot space, rotated by yaw so the
    /// close-up follows the room and her. `photo` is a wall photo to fly up to and look at straight on, in world space.
    func update(dt: Float, framing: CatRoom.Framing, focusDistance: Float,
                yaw: Float, focus: SIMD3<Float>, photo pose: (center: SIMD3<Float>, normal: SIMD3<Float>)?,
                adjust: ((Float, CameraPose) -> CameraPose)? = nil) {
        self.framing = framing
        self.focusDistance = focusDistance
        zoom += (targetZoom - zoom) * min(1, dt * 10)
        if abs(targetZoom - zoom) < 0.0005 { zoom = targetZoom }
        if let pose { photoPose = pose }
        let goal: Float = pose == nil ? 0 : 1
        photo += (goal - photo) * min(1, dt * 3.2)
        if abs(goal - photo) < 0.0005 { photo = goal }
        apply(zoom: zoom, yaw: yaw, focus: focus, dt: dt, adjust: adjust)
    }

    private func apply(zoom z: Float, yaw: Float, focus: SIMD3<Float>, dt: Float = 0,
                       adjust: ((Float, CameraPose) -> CameraPose)? = nil) {
        let distance = framing.far + (framing.near - framing.far) * z
        let rotatedCat = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(focus)
        var target = framing.target + (rotatedCat - framing.target) * z
        var eye = target + framing.direction * distance
        if photo > 0, let photoPose {
            let s = photo * photo * (3 - 2 * photo)
            target = simd_mix(target, photoPose.center, SIMD3(repeating: s))
            eye = simd_mix(eye, photoPose.center + photoPose.normal * focusDistance, SIMD3(repeating: s))
        }
        if let adjust {
            let pose = adjust(dt, CameraPose(eye: eye, target: target))
            (eye, target) = (pose.eye, pose.target)
        }
        // A pose written again is a camera that moved, to everything that follows it.
        guard target != placed?.target || eye != placed?.eye else { return }
        placed = (target, eye)
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}
