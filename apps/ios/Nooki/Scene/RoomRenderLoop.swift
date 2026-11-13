import Metal
import QuartzCore
import RealityKit
import SwiftUI
import UIKit

/// The room drawn by a `RealityRenderer` into a layer of our own, on our own display link, so the frame rate is ours:
/// a still room costs 30 frames a second and a covered or hidden one none. Where `RealityView` draws every frame it
/// exists, with no way to pause or cap it (docs/perf/idle-world-heat.md, 3.1).
///
/// One loop for the app's life, owned by `RoomController`: the renderer and its entities are never torn down, which is
/// what a `RealityView` that goes away does to the GPU side of a room (the blank room of #618).
@MainActor
final class RoomRenderLoop: RoomSurface {
    let view = MetalRoomView()
    let rig = ZoomRig()

    private let renderer: RealityRenderer
    private var link: CADisplayLink?
    private var target = DisplayLinkTarget()
    private var scene: CatRoom?
    private var last: CFTimeInterval?
    private var fast = false
    private var running = false
    private var idleRate = RoomRenderLoop.range(30)
    private var activeRate = RoomRenderLoop.range(60)

    /// Nil where RealityKit cannot make a renderer; the room then stays on `RealityView`.
    init?() {
        guard let renderer = try? RealityRenderer() else { return nil }
        self.renderer = renderer
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
        renderer.cameraSettings.antialiasing = .none
        renderer.entities.append(rig.camera)
        renderer.activeCamera = rig.camera
        target.tick = { [weak self] link in self?.frame(link) }
    }

    var camera: RoomCamera {
        RoomCamera(transform: rig.camera.transformMatrix(relativeTo: nil),
                   fovDegrees: rig.camera.camera.fieldOfViewInDegrees, size: view.bounds.size)
    }

    func setAntialiasing(_ on: Bool) {
        renderer.cameraSettings.antialiasing = on ? .multisample4X : .none
    }

    /// The frames a second while something moves and while nothing does, and the pixels across per point, as the quality
    /// tier says.
    func setQuality(_ rendering: RoomRendering) {
        idleRate = Self.range(rendering.idleRate)
        activeRate = Self.range(min(rendering.activeRate, 120))
        view.scaleCap = CGFloat(rendering.scale)
        if let link { link.preferredFrameRateRange = fast ? activeRate : idleRate }
    }

    /// Puts `room` in the renderer in place of any other; the camera stays.
    func show(_ room: CatRoom) {
        guard scene !== room else { return }
        if let scene { renderer.entities.remove(scene.root) }
        scene = room
        renderer.entities.append(room.root)
    }

    /// Frames run only while the room is on screen and not under a cover; the last one stays showing otherwise.
    func setRunning(_ on: Bool) {
        guard on != running else { return }
        running = on
        last = nil
        if on { startLink() } else { link?.isPaused = true }
    }

    func updates(_ handler: @escaping (SceneEvents.Update) -> Void) -> EventSubscription {
        renderer.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil, handler)
    }

    func project(_ point: SIMD3<Float>) -> CGPoint? { camera.project(point) }

    func unproject(_ point: CGPoint, ontoPlane plane: simd_float4x4) -> SIMD3<Float>? {
        camera.unproject(point, ontoPlane: plane)
    }

    private func startLink() {
        if let link {
            link.isPaused = false
            return
        }
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.frame))
        link.preferredFrameRateRange = fast ? activeRate : idleRate
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    /// Exactly `rate`, or as close as the screen's own steps allow.
    private static func range(_ rate: Int) -> CAFrameRateRange {
        let hertz = Float(max(rate, 10))
        return CAFrameRateRange(minimum: hertz <= 30 ? max(hertz - 6, 10) : hertz, maximum: hertz, preferred: hertz)
    }

    private func frame(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { last = now }
        let wantsFast = scene?.isActive ?? false
        if wantsFast != fast {
            fast = wantsFast
            link.preferredFrameRateRange = wantsFast ? activeRate : idleRate
        }
        guard let last, let drawable = view.metalLayer.nextDrawable() else { return }
        let dt = min(now - last, 0.1)
        do {
            let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: drawable.texture))
            let shown = UncheckedDrawable(drawable: drawable)
            try renderer.updateAndRender(deltaTime: dt, cameraOutput: output, onComplete: { _ in
                shown.drawable.present()
            })
        } catch {
            print("Room renderer failed: \(error)")
        }
    }
}

/// A drawable handed to the renderer's completion, which runs off the main thread; presenting one is thread-safe.
private struct UncheckedDrawable: @unchecked Sendable {
    let drawable: any CAMetalDrawable
}

/// A display link holds its target strongly; this keeps that target from being the loop.
private final class DisplayLinkTarget: NSObject {
    var tick: (CADisplayLink) -> Void = { _ in }

    @objc func frame(_ link: CADisplayLink) { tick(link) }
}

/// The layer the room is drawn into: transparent over the backdrop, at most `scaleCap` pixels across a point (twice, at
/// the best look), since three times is more pixels than clay and splats show.
final class MetalRoomView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var scaleCap: CGFloat = 2 {
        didSet { if scaleCap != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 2
    }

    required init?(coder: NSCoder) { fatalError("MetalRoomView is made in code") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(traitCollection.displayScale, scaleCap)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

/// The loop's one view, handed to SwiftUI again each time it asks.
struct RoomCanvas: UIViewRepresentable {
    let loop: RoomRenderLoop

    func makeUIView(context: Context) -> MetalRoomView { loop.view }

    func updateUIView(_ view: MetalRoomView, context: Context) {}
}
