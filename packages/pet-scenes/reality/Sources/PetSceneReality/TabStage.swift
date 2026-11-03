import CoreGraphics
import Foundation
import Observation
import PetScene
import RealityKit
import SwiftUI

/// A 3D scene that fills a tab of its own, the shop or the desk: built in code from the styled
/// rooms' shared meshes and materials, stepped from the display, and lit warm.
@MainActor
protocol TabStage: AnyObject {
  var root: Entity { get }
  var screen: TabScreen { get }
  /// Builds the scene the first time, and starts stepping it.
  func start()
  func setOnScreen(_ onScreen: Bool)
  func setReduceMotion(_ reduced: Bool)
  /// Lights the scene with a lighting preset, through the same rig as the styled rooms.
  func setLighting(_ look: LightingLook)
  func fit(to size: CGSize)
  func orbit(byX deltaX: Float, y deltaY: Float)
  func endOrbit(velocityX: Float, velocityY: Float)
  func tap(_ entity: Entity)
}

/// A soft round of light drawn over a scene in screen blend, where a lamp or a bulb is.
struct TabGlow: Hashable {
  var centre: CGPoint
  var radius: CGFloat
  var colour: GenzColour
  var strength: Double
}

/// What the flat layers over a tab's scene need, in the view's points.
@MainActor
@Observable
final class TabScreen {
  var glows: [TabGlow] = []
  /// The corners of a window in the view, which the preset's haze leaves clear.
  var window: [CGPoint] = []
  /// True once the scene is built and lit, so the glow can come up with it.
  var isLit = false
  /// How much of the view is still dark, as while a scene fades up out of the night.
  var darkness = 0.0
}

/// The camera of a tab's scene: the styled rooms' orbit, held to a small turn so the scene stays
/// framed, and the lens that follows it.
@MainActor
final class TabCamera {
  let lens = PerspectiveCamera()
  private(set) var camera: GenzCamera
  private(set) var size = CGSize(width: 393, height: 852)
  private var lastPosition = SIMD3<Float>.zero

  private static let orbitPerPoint: Float = 0.003
  /// The lens's clip planes. The rooms stand some twenty units off and never closer than a few,
  /// so a near plane this far out keeps the depth fine enough for the shadows and paper lying
  /// close over what is under them.
  static let nearClip: Float = 1
  static let farClip: Float = 200

  private let home: GenzCamera.Home

  init(home: GenzCamera.Home) {
    self.home = home
    camera = GenzCamera(home: home)
    lens.camera.fieldOfViewInDegrees = home.fieldOfView
    lens.camera.near = Self.nearClip
    lens.camera.far = Self.farClip
    aim()
  }

  var position: SIMD3<Float> { camera.position }

  func fit(to size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    self.size = size
    camera.fit(to: SIMD2(Float(size.width), Float(size.height)))
    aim()
  }

  /// Holds the camera off its place by a turn, a lift and a distance multiple, as in a flight.
  func fly(yaw: Float, pitch: Float, distance: Float) {
    camera.fly(yaw: yaw, pitch: pitch, distance: distance)
    aim()
  }

  func orbit(byX deltaX: Float, y deltaY: Float) {
    camera.drag(yaw: -deltaX * Self.orbitPerPoint, pitch: deltaY * Self.orbitPerPoint)
    aim()
  }

  /// Lets go of a drag. A tab's scene is framed for one view, so it eases back there after a look
  /// around, or jumps back when motion is reduced.
  func release(animated: Bool) {
    camera.release(yawVelocity: 0, pitchVelocity: 0, coasting: false)
    camera.goHome(animated: animated)
  }

  /// Steps the coast and the way home. True when the camera moved, so the overlays follow.
  func step(_ delta: Float) -> Bool {
    camera.step(delta)
    aim()
    let moved = simd_distance(lastPosition, camera.position) > 0.0005
    lastPosition = camera.position
    return moved
  }

  /// Where a point of the scene lands in the view.
  func project(_ point: SIMD3<Float>) -> CGPoint? {
    camera.project(point, in: size)
  }

  /// Where `point` is in the view as the camera sees it from its home place.
  func projectFromHome(_ point: SIMD3<Float>) -> CGPoint? {
    GenzCamera(home: home).project(point, in: size)
  }

  /// How many points across a length of `span` at `point` covers in the view.
  func reach(_ span: Float, at point: SIMD3<Float>) -> CGFloat {
    let depth = max(simd_distance(point, camera.position), 0.01)
    let half = tan(camera.fieldOfView * .pi / 360) * depth
    return CGFloat(span / (2 * half)) * size.height
  }

  private func aim() {
    lens.look(at: camera.target, from: camera.position, relativeTo: lens.parent)
  }
}

/// Shared light and paint for the tab scenes.
@MainActor
enum TabLook {
  /// Image-based light from a vertical gradient: `top` from above, `bottom` from below.
  static func ambient(top: GenzColour, bottom: GenzColour) -> EnvironmentResource? {
    guard let image = gradient([bottom, top], width: 64, height: 32) else { return nil }
    return try? EnvironmentResource(equirectangular: image)
  }

  /// A point light.
  static func bulb(_ colour: GenzColour, intensity: Float, reach: Float, at point: GenzRoomPoint)
    -> Entity
  {
    let light = Entity()
    light.position = point.scene
    light.components.set(
      PointLightComponent(
        color: colour.platformColour, intensity: intensity, attenuationRadius: reach))
    return light
  }

  /// A gradient from the first colour at the bottom to the last at the top.
  static func gradient(_ colours: [GenzColour], width: Int, height: Int) -> CGImage? {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let gradient = CGGradient(
        colorsSpace: space, colors: colours.map(\.cgColor) as CFArray, locations: nil)
    else { return nil }
    context.drawLinearGradient(
      gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    return context.makeImage()
  }

  /// An unlit material showing `image`, darkened towards `tint`.
  static func picture(_ image: CGImage, tint: GenzColour = GenzColour(0xFFFFFF)) -> UnlitMaterial? {
    guard let texture = try? TextureResource(image: image, options: .init(semantic: .color))
    else { return nil }
    var material = UnlitMaterial()
    material.color = .init(tint: tint.platformColour, texture: .init(texture))
    return material
  }

  /// Makes `entity` answer taps over its visual bounds, a little enlarged so small things are easy
  /// to hit.
  static func makeTappable(_ entity: Entity, margin: Float = 0.1) {
    let bounds = entity.visualBounds(relativeTo: entity)
    guard !bounds.isEmpty else { return }
    NookiDiorama.makeTappable(
      entity, size: bounds.extents + SIMD3(repeating: margin * 2), center: bounds.center)
  }

  /// The first entity from `entity` up whose name starts with `prefix`, and the rest of its name.
  static func named(_ prefix: String, from entity: Entity) -> (Entity, String)? {
    var current: Entity? = entity
    while let found = current {
      if found.name.hasPrefix(prefix) { return (found, String(found.name.dropFirst(prefix.count))) }
      current = found.parent
    }
    return nil
  }
}

/// The tab scenes of one pet scene, each built once and kept, sharing the styled rooms' meshes,
/// materials and cats.
@MainActor
final class TabStages {
  private let rooms: GenzRoomCache
  private var shop: ShopStage?
  private var desk: DeskStage?
  private var onboarding: OnboardingStage?
  private var adoption: AdoptionStage?
  private var rehearsed: Set<ObjectIdentifier> = []

  nonisolated init(rooms: GenzRoomCache) {
    self.rooms = rooms
  }

  /// True the first time it is asked for `stage`, which ``TabRehearsal`` then draws; once a launch.
  func claimRehearsal(of stage: any TabStage) -> Bool {
    rehearsed.insert(ObjectIdentifier(stage)).inserted
  }

  var shopStage: ShopStage {
    if let shop { return shop }
    let made = ShopStage(kit: rooms.kit)
    shop = made
    return made
  }

  var deskStage: DeskStage {
    if let desk { return desk }
    let made = DeskStage(kit: rooms.kit, cats: rooms.cats)
    desk = made
    return made
  }

  var onboardingStage: OnboardingStage {
    if let onboarding { return onboarding }
    let made = OnboardingStage(kit: rooms.kit)
    onboarding = made
    return made
  }

  var adoptionStage: AdoptionStage {
    if let adoption { return adoption }
    let made = AdoptionStage(kit: rooms.kit, cats: rooms.cats)
    adoption = made
    return made
  }
}

/// Shows a tab's scene: a warm backdrop, the 3D scene, then its glow.
///
/// The RealityView mounts only once the host shows the tab, because one mounted out of sight
/// never draws, and then stays. Its stage steps from the display and pauses off screen.
struct TabSceneView: View {
  let stage: any TabStage
  /// Drawn behind the scene, as the view through a window, in the points the stage projects into.
  var behind: AnyView?
  /// Drawn over everything else, in the same points the stage projects into.
  var overlay: AnyView?

  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.petSceneLighting) private var lighting
  @State private var isMounted = false
  @State private var isAppeared = false
  @State private var track = GestureTrack()
  /// Set a moment after the RealityView mounts, as its first frame takes that long to come.
  @State private var isDrawing = false

  /// Whatever is laid over the scene waits for it to be lit and drawn.
  private var showsLayers: Bool { stage.screen.isLit && isDrawing }

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  var body: some View {
    let look = LightingLook.of(lighting)
    ZStack {
      TabBackdrop()
      if showsLayers, let behind { behind.transition(.opacity) }
      GlowHaze(look: look, window: stage.screen.window)
      if isMounted { reality }
      TabGlowLayer(screen: stage.screen).opacity(isDrawing ? 1 : 0)
      GlowGrade(look: look)
      GlowVignette(look: look)
      if stage.screen.darkness > 0 {
        Color.black.opacity(stage.screen.darkness)
          .ignoresSafeArea()
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      if showsLayers, let overlay { overlay.transition(.opacity) }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showsLayers)
    .ignoresSafeArea()
    .onAppear { isAppeared = true }
    .onDisappear { isAppeared = false }
    .onChange(of: isOnScreen, initial: true) { _, onScreen in
      if onScreen { isMounted = true }
      stage.setOnScreen(onScreen)
    }
    .onChange(of: reduceMotion, initial: true) { _, reduced in stage.setReduceMotion(reduced) }
    .onChange(of: lighting, initial: true) { _, lighting in stage.setLighting(.of(lighting)) }
  }

  private static let firstFrame = Duration.milliseconds(450)

  private var reality: some View {
    let stage = stage
    return RealityView { content in
      content.camera = .virtual
      content.add(stage.root)
      stage.start()
    }
    .task {
      try? await Task.sleep(for: Self.firstFrame)
      isDrawing = true
    }
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      stage.fit(to: $0)
    }
    .gesture(
      SpatialTapGesture()
        .targetedToAnyEntity()
        .onEnded { stage.tap($0.entity) }
    )
    .simultaneousGesture(
      DragGesture(minimumDistance: 8)
        .onChanged { value in
          stage.orbit(
            byX: Float(value.translation.width - track.drag.width),
            y: Float(value.translation.height - track.drag.height))
          track.drag = value.translation
        }
        .onEnded { value in
          track.drag = .zero
          stage.endOrbit(
            velocityX: Float(value.velocity.width), velocityY: Float(value.velocity.height))
        }
    )
  }
}

/// The warm dark the scene floats in.
private struct TabBackdrop: View {
  var body: some View {
    RadialGradient(
      colors: [
        Color(cgColor: GenzColour(0x4A2C26).cgColor), Color(cgColor: GenzColour(0x160D12).cgColor),
      ],
      center: UnitPoint(x: 0.5, y: 0.42), startRadius: 20, endRadius: 560
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

/// The lamps' halos, in screen blend over the scene.
private struct TabGlowLayer: View {
  let screen: TabScreen

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      ForEach(Array(screen.glows.enumerated()), id: \.offset) { _, glow in
        let colour = Color(cgColor: glow.colour.cgColor)
        Circle()
          .fill(
            RadialGradient(
              colors: [colour.opacity(glow.strength), colour.opacity(0)], center: .center,
              startRadius: 0, endRadius: glow.radius)
          )
          .frame(width: glow.radius * 2, height: glow.radius * 2)
          .position(glow.centre)
      }
    }
    .blendMode(.screen)
    .opacity(screen.isLit ? 1 : 0)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: screen.isLit)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
