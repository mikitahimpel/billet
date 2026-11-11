import RealityKit
import RoomInterface
import SwiftUI

struct DioramaView: View {
    let scene: CatRoom
    /// Off-screen, the room stops animating and drawing.
    let paused: Bool
    let petPulse: Int
    let rendering: RoomRendering
    var onPet: () -> Void

    @State private var rig = ZoomRig()
    @State private var dragStartYaw: Float?
    @State private var pinchStartZoom: Float?
    @State private var bubble = BubbleSpot()
    @State private var photoFocused = false

    /// Shows `scene` in place of any other room and drives it from this view's frames.
    private func attach(_ scene: CatRoom, to content: RealityViewCameraContent) {
        for entity in Array(content.entities) where entity !== rig.camera { content.remove(entity) }
        content.add(scene.root)
        scene.paused = paused
        scene.unprojector = { point, plane in content.unproject(point, from: .local, to: .scene, ontoPlane: plane) }
        scene.onFocusChange = { focused in withAnimation(.easeOut(duration: 0.3)) { photoFocused = focused } }
        let bubble = bubble
        scene.start(updatesFrom: content, viewer: rig.camera, beforeProjecting: { dt in
            rig.update(dt: dt, framing: scene.framing, focusDistance: scene.focusDistance,
                       yaw: scene.settledYaw, focus: scene.catFocus, photo: scene.photoPose)
        }) { projected in
            guard let projected else { return }
            if let old = bubble.point, hypot(old.x - projected.x, old.y - projected.y) < 2 { return }
            bubble.point = projected
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
        .overlay { BubbleOverlay(spot: bubble, pulse: petPulse).opacity(photoFocused ? 0 : 1) }
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
                .onEnded { value in
                    if scene.focusedPhoto != nil { return scene.unfocusPhoto() }
                    // HomeView plays the purr when the pet lands, the same way for taps and widget pets.
                    guard scene.isCat(value.entity) else { return scene.tapped(value.entity) }
                    onPet()
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .targetedToAnyEntity()
                .onEnded { value in
                    if scene.focusedPhoto != nil { return scene.unfocusPhoto() }
                    scene.doubleTapped(value.entity)
                }
        )
        // Taps on empty space, which the entity-targeted gestures never see, also leave a photo.
        .simultaneousGesture(SpatialTapGesture().onEnded { _ in scene.unfocusPhoto() })
        .simultaneousGesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
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
                    scene.follow(nil)
                }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    guard !photoFocused else { return }
                    let start = pinchStartZoom ?? rig.targetZoom
                    pinchStartZoom = start
                    let delta = Float(log2(Double(value.magnification))) * 0.6
                    rig.targetZoom = min(max(start + delta, 0), 1)
                }
                .onEnded { _ in pinchStartZoom = nil }
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
private final class ZoomRig {
    let camera = PerspectiveCamera()
    var targetZoom: Float = 0.25
    private var zoom: Float = 0.25

    private var framing = CatRoom.Framing()
    private var focusDistance: Float = 0.8
    private var photo: Float = 0
    private var photoPose: (center: SIMD3<Float>, normal: SIMD3<Float>)?
    private var placed: (target: SIMD3<Float>, eye: SIMD3<Float>)?

    init() {
        camera.camera.fieldOfViewInDegrees = 22
        apply(zoom: zoom, yaw: 0, focus: [0.06, 0.12, -0.04])
    }

    /// `framing` and `focusDistance` come from the room, `focus` is Mochi's head in pivot space, rotated by yaw so the
    /// close-up follows the room and her. `photo` is a wall photo to fly up to and look at straight on, in world space.
    func update(dt: Float, framing: CatRoom.Framing, focusDistance: Float,
                yaw: Float, focus: SIMD3<Float>, photo pose: (center: SIMD3<Float>, normal: SIMD3<Float>)?) {
        self.framing = framing
        self.focusDistance = focusDistance
        zoom += (targetZoom - zoom) * min(1, dt * 10)
        if abs(targetZoom - zoom) < 0.0005 { zoom = targetZoom }
        if let pose { photoPose = pose }
        let goal: Float = pose == nil ? 0 : 1
        photo += (goal - photo) * min(1, dt * 3.2)
        if abs(goal - photo) < 0.0005 { photo = goal }
        apply(zoom: zoom, yaw: yaw, focus: focus)
    }

    private func apply(zoom z: Float, yaw: Float, focus: SIMD3<Float>) {
        let distance = framing.far + (framing.near - framing.far) * z
        let rotatedCat = simd_quatf(angle: yaw, axis: [0, 1, 0]).act(focus)
        var target = framing.target + (rotatedCat - framing.target) * z
        var eye = target + framing.direction * distance
        if photo > 0, let photoPose {
            let s = photo * photo * (3 - 2 * photo)
            target = simd_mix(target, photoPose.center, SIMD3(repeating: s))
            eye = simd_mix(eye, photoPose.center + photoPose.normal * focusDistance, SIMD3(repeating: s))
        }
        // A pose written again is a camera that moved, to everything that follows it.
        guard target != placed?.target || eye != placed?.eye else { return }
        placed = (target, eye)
        camera.look(at: target, from: eye, relativeTo: nil)
    }
}
