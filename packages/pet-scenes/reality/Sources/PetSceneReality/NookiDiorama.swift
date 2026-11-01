import CoreGraphics
import Foundation
import OSLog
import Pet
import RealityKit
import SwiftUI

/// The room and everything that moves in it. Metres, with the floor's top at y = 0 and the two
/// walls along x = -0.6 and z = -0.6.
@MainActor
final class NookiDiorama {
  let root = Entity()

  private let lens = PerspectiveCamera()
  private let mochi = Entity()
  private let note = Entity()
  private var closedEyes: [Entity] = []
  private var openEyes: [Entity] = []
  private var ears: [Entity] = []
  private var world = PetWorld()
  private var clock = 0.0
  private var lastDelta: Float = 0
  private var stepStart = 0.0
  private var subscription: EventSubscription?
  private var camera = NookiCamera()
  private var reduceMotion = false
  private let windowLight = Entity()
  private var windowPane: ModelEntity?
  /// Eased 0...1 towards the frame's light.
  private var light: Float = 0

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "NookiDiorama")

  private static let orbitPerPoint: Float = 0.006

  // Mochi lies in the bed in the middle of the rug, turned towards the camera.
  private static let mochiPosition: SIMD3<Float> = [0.05, 0.095, 0.12]
  private static let mochiYaw: Float = 3.8
  /// Extra turn towards the note wall when awake.
  private static let wakeTurn: Float = 0.5
  private static let noteHome: SIMD3<Float> = [0.08, 0.46, -0.565]
  private static let noteStart: SIMD3<Float> = [0.75, 1.05, -0.1]
  /// Extra turn towards the window when the partner is here.
  private static let lookTurn: Float = -0.55
  private static let windowCentre: SIMD3<Float> = [-0.28, 0.52, -0.59]
  private static let lightPerSecond: Float = 1.5

  init() {
    buildRoom()
    buildNote()
    mochi.position = Self.mochiPosition
    root.addChild(mochi)
    lens.camera.fieldOfViewInDegrees = 30
    root.addChild(lens)
    aimLens()
  }

  /// Loads the models. A missing asset leaves a gap in the room and is logged.
  func load() async {
    await place("Item_rug", width: 0.86, at: [0.05, 0.002, 0.12], yaw: 0)
    await place("Item_donutbed", width: 0.5, at: [0.05, 0.012, 0.12], yaw: 0)
    await place("Item_bookcase", height: 0.72, at: [-0.46, 0, -0.1], yaw: .pi / 2)
    await place("Item_monstera", height: 0.62, at: [-0.4, 0, -0.42], yaw: 0)
    await place("Item_lamp", height: 0.4, at: [0.52, 0, -0.08], yaw: 0)
    await loadMochi()
    await addLighting()
  }

  /// Shows `world` from the start of its step.
  func show(_ world: PetWorld) {
    guard world != self.world else { return }
    let sameStep = world.step == self.world.step
    self.world = world
    guard !sameStep else { return }
    stepStart = clock
    apply(elapsed: 0)
  }

  func startUpdates(from content: RealityViewCameraContent) {
    subscription = content.subscribe(
      to: SceneEvents.Update.self, on: nil, componentType: nil
    ) { [weak self] event in
      let delta = event.deltaTime
      MainActor.assumeIsolated {
        self?.tick(delta)
      }
    }
  }

  func setReduceMotion(_ reduced: Bool) {
    reduceMotion = reduced
  }

  // MARK: - Camera

  /// Follows a drag, in screen points since the last step.
  func orbit(byX deltaX: Float, y deltaY: Float) {
    camera.drag(yaw: -deltaX * Self.orbitPerPoint, pitch: deltaY * Self.orbitPerPoint)
    aimLens()
  }

  /// Lets go of a drag, with its velocity in points per second.
  func endOrbit(velocityX: Float, velocityY: Float) {
    camera.release(
      yawVelocity: -velocityX * Self.orbitPerPoint,
      pitchVelocity: velocityY * Self.orbitPerPoint,
      coasting: !reduceMotion)
  }

  func zoom(by scale: Float) {
    camera.zoom(by: scale)
    aimLens()
  }

  func endZoom() {
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: !reduceMotion)
  }

  func returnCameraHome() {
    camera.goHome(animated: !reduceMotion)
    aimLens()
  }

  private func aimLens() {
    lens.look(at: NookiCamera.target, from: camera.position, relativeTo: nil)
  }

  private func tick(_ delta: TimeInterval) {
    clock += delta
    lastDelta = Float(delta)
    if !camera.isAtRest {
      camera.step(Float(delta))
      aimLens()
    }
    apply(elapsed: clock - stepStart)
  }

  private func apply(elapsed: Double) {
    let frame = NookiChoreography.frame(world, elapsed: elapsed)
    let breath = 0.018 * sin(Float(clock) * 1.6) * (1 - frame.wake)
    mochi.scale = [
      1 - 0.04 * frame.wake + breath * 0.5,
      1 + 0.14 * frame.wake + breath,
      1 - 0.04 * frame.wake + breath * 0.5,
    ]
    mochi.position = Self.mochiPosition + [0, 0.02 * frame.wake + 0.05 * frame.hop, 0]
    if frame.light != light { easeLight(to: frame.light) }
    mochi.orientation = simd_quatf(
      angle: Self.mochiYaw + Self.wakeTurn * frame.wake + Self.lookTurn * light,
      axis: [0, 1, 0])

    for eye in closedEyes { eye.isEnabled = !frame.eyesOpen }
    for eye in openEyes { eye.isEnabled = frame.eyesOpen }
    for ear in ears { ear.scale = .one * (1 + 0.15 * frame.wake) }

    note.isEnabled = frame.note > 0
    note.position = mix(Self.noteStart, Self.noteHome, t: frame.note)
    note.scale = .one * (0.3 + 0.7 * frame.note)
    let swing = 0.2 * sin(Float(elapsed) * 3) * (1 - frame.note)
    note.orientation = simd_quatf(angle: swing, axis: [0, 0, 1])
  }

  private func easeLight(to target: Float) {
    let toward = target - light
    let step = reduceMotion ? abs(toward) : Self.lightPerSecond * lastDelta
    light = abs(toward) <= step ? target : light + (toward < 0 ? -step : step)
    windowLight.components.set(
      PointLightComponent(color: Tone.glow.color, intensity: 900 * light, attenuationRadius: 1.2))
    windowPane?.model?.materials = [Self.glass(light: light)]
  }

  // MARK: - Room

  private func buildRoom() {
    box([1.3, 0.08, 1.3], .honey, at: [0.05, -0.04, 0.05])
    box([0.06, 0.86, 1.3], .plaster, at: [-0.63, 0.43, 0.05])
    box([1.36, 0.86, 0.06], .plaster, at: [0.02, 0.43, -0.63])
    box([0.012, 0.09, 1.2], .walnut, at: [-0.594, 0.045, 0.05])
    box([1.2, 0.09, 0.012], .walnut, at: [0.05, 0.045, -0.594])
    box([1.05, 0.006, 0.006], .ink, at: [0.05, 0.6, -0.59])
    buildWindow()
  }

  /// A small window on the back wall. Its pane glows and a light spills into the room while the
  /// partner is here.
  private func buildWindow() {
    box([0.25, 0.3, 0.014], .walnut, at: Self.windowCentre + [0, 0, 0.004])
    let pane = ModelEntity(
      mesh: .generateBox(width: 0.21, height: 0.26, depth: 0.004),
      materials: [Self.glass(light: 0)])
    pane.position = Self.windowCentre + [0, 0, 0.013]
    root.addChild(pane)
    windowPane = pane
    windowLight.position = Self.windowCentre + [0, 0, 0.25]
    root.addChild(windowLight)
  }

  private static func glass(light: Float) -> PhysicallyBasedMaterial {
    var material = clay(.night)
    material.emissiveColor = .init(color: Tone.glow.color)
    material.emissiveIntensity = 2.5 * light
    return material
  }

  private func buildNote() {
    let sheet = ModelEntity(
      mesh: .generateBox(width: 0.22, height: 0.28, depth: 0.004),
      materials: [Self.clay(.paper)])
    note.addChild(sheet)
    let mark = ModelEntity(
      mesh: .generateSphere(radius: 0.022), materials: [Self.clay(.heart)])
    mark.position = [0, -0.02, 0.003]
    mark.scale = [1, 1, 0.1]
    note.addChild(mark)
    let peg = ModelEntity(
      mesh: .generateBox(width: 0.018, height: 0.05, depth: 0.012),
      materials: [Self.clay(.walnut)])
    peg.position = [0, 0.14, 0.006]
    note.addChild(peg)
    note.isEnabled = false
    root.addChild(note)
  }

  private func box(_ size: SIMD3<Float>, _ tone: Tone, at position: SIMD3<Float>) {
    let model = ModelEntity(
      mesh: .generateBox(size: size, cornerRadius: 0.004), materials: [Self.clay(tone)])
    model.position = position
    root.addChild(model)
  }

  private func place(
    _ name: String,
    width: Float? = nil,
    height: Float? = nil,
    at position: SIMD3<Float>,
    yaw: Float
  ) async {
    do {
      let model = try await Entity(named: name, in: .module)
      let bounds = model.visualBounds(relativeTo: nil)
      let scale =
        width.map { $0 / max(bounds.extents.x, bounds.extents.z) }
        ?? height.map { $0 / bounds.extents.y } ?? 1
      model.scale = .one * scale
      model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
      let holder = Entity()
      holder.position = position
      holder.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
      holder.addChild(model)
      root.addChild(holder)
    } catch {
      Self.log.error("Loading \(name) failed: \(String(describing: error))")
    }
  }

  // MARK: - Mochi

  private func loadMochi() async {
    do {
      let model = try await Entity(named: "Cat", in: .module)
      let bounds = model.visualBounds(relativeTo: nil)
      model.scale = .one * 1.25
      model.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * 1.25
      mochi.addChild(model)
      findFeatures(in: model)
    } catch {
      Self.log.error("Loading Cat failed: \(String(describing: error))")
    }
  }

  private func findFeatures(in model: Entity) {
    closedEyes = ["Eye1", "Eye_1"].compactMap { model.findEntity(named: $0) }
    ears = ["Ear1", "Ear_1", "EarInner1", "EarInner_1"].compactMap { model.findEntity(named: $0) }
    openEyes = closedEyes.map { closed in
      let eye = ModelEntity(mesh: .generateSphere(radius: 0.012), materials: [Self.clay(.ink)])
      eye.position = closed.position(relativeTo: model)
      eye.isEnabled = false
      model.addChild(eye)
      return eye
    }
  }

  // MARK: - Light

  private func addLighting() async {
    if let image = Self.ambientGradient(),
      let environment = try? await EnvironmentResource(equirectangular: image)
    {
      let ambient = Entity()
      ambient.components.set(
        ImageBasedLightComponent(source: .single(environment), intensityExponent: 0.6))
      root.addChild(ambient)
      let receiver = ImageBasedLightReceiverComponent(imageBasedLight: ambient)
      Self.visit(root) { $0.components.set(receiver) }
    }

    let sun = Entity()
    sun.components.set(
      DirectionalLightComponent(color: Tone.lamp.color, intensity: 1800))
    sun.components.set(DirectionalLightComponent.Shadow(maximumDistance: 4, depthBias: 2))
    sun.look(at: .zero, from: [1.2, 2.4, 1.6], relativeTo: nil)
    root.addChild(sun)

    let lamp = Entity()
    lamp.position = [0.46, 0.5, -0.02]
    lamp.components.set(
      PointLightComponent(color: Tone.lamp.color, intensity: 2200, attenuationRadius: 1.4))
    root.addChild(lamp)
  }

  private static func visit(_ entity: Entity, _ body: (Entity) -> Void) {
    body(entity)
    for child in entity.children { visit(child, body) }
  }

  /// A warm vertical gradient for ambient light: bright above, like a ceiling in lamplight.
  private static func ambientGradient() -> CGImage? {
    let colors = [Tone.ceiling.cgColor, Tone.bounce.cgColor] as CFArray
    guard
      let context = CGContext(
        data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
    else { return nil }
    context.drawLinearGradient(
      gradient, start: CGPoint(x: 0, y: 32), end: .zero, options: [])
    return context.makeImage()
  }

  private static func clay(_ tone: Tone) -> PhysicallyBasedMaterial {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(tint: tone.color)
    material.roughness = 0.85
    material.metallic = 0.0
    return material
  }
}

private enum Tone {
  case honey, plaster, walnut, ink, paper, heart, lamp, ceiling, bounce, night, glow

  private var rgb: (CGFloat, CGFloat, CGFloat) {
    switch self {
    case .honey: (0.72, 0.5, 0.3)
    case .plaster: (0.56, 0.68, 0.72)
    case .walnut: (0.36, 0.23, 0.16)
    case .ink: (0.1, 0.08, 0.08)
    case .paper: (0.98, 0.96, 0.9)
    case .heart: (0.85, 0.27, 0.27)
    case .lamp: (1, 0.87, 0.72)
    case .ceiling: (1, 0.93, 0.82)
    case .bounce: (0.6, 0.47, 0.4)
    case .night: (0.12, 0.16, 0.26)
    case .glow: (1, 0.82, 0.5)
    }
  }

  var color: RealityKit.Material.Color {
    RealityKit.Material.Color(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
  }
  var cgColor: CGColor { CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
}
