import DesignSystem
import Pet
import RealityKit
import SwiftUI

/// The one live preview the shop shows. It keeps a single scene and swaps the item in it, so
/// moving from card to card never starts another renderer.
struct NookiShopPreview: View {
  let item: ShopItem

  @State private var stage = NookiPreviewStage()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.add(stage.root)
      stage.start(from: content)
    }
    .task(id: item) { await stage.show(item) }
    .onChange(of: reduceMotion, initial: true) { _, reduced in stage.setSpinning(!reduced) }
    .onChange(of: scenePhase, initial: true) { _, phase in stage.setRunning(phase == .active) }
    .onDisappear { stage.setRunning(false) }
    .onAppear { stage.setRunning(scenePhase == .active) }
  }
}

/// The preview's scene: a lit spot, a camera, and a turntable holding the shown item.
@MainActor
final class NookiPreviewStage {
  let root = Entity()
  private let turntable = Entity()
  private let models = NookiShopModels()
  private var subscription: EventSubscription?
  private var shown: ShopItem.ID?
  private var angle: Float = 0.5
  private var isSpinning = true
  private var isRunning = true

  private static let radiansPerSecond: Float = 0.9
  /// The longest side of whatever is shown, in metres.
  private static let span: Float = 0.5

  init() {
    let lens = PerspectiveCamera()
    lens.camera.fieldOfViewInDegrees = 30
    lens.look(at: [0, 0.2, 0], from: [0, 0.42, 1.25], relativeTo: nil)
    root.addChild(lens)

    let key = DirectionalLight()
    key.light.color = Self.warm
    key.light.intensity = 3500
    key.look(at: .zero, from: [0.6, 1.2, 1.0], relativeTo: nil)
    root.addChild(key)
    let fill = PointLight()
    fill.light.color = Self.warm
    fill.light.intensity = 9000
    fill.light.attenuationRadius = 4
    fill.position = [-0.9, 0.5, 0.9]
    root.addChild(fill)

    root.addChild(turntable)
    turntable.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
  }

  private static var warm: RealityKit.Material.Color {
    let swatch = Palette.lightWarm
    return .init(
      red: CGFloat(swatch.red) / 255, green: CGFloat(swatch.green) / 255,
      blue: CGFloat(swatch.blue) / 255, alpha: 1)
  }

  func start(from content: RealityViewCameraContent) {
    subscription = content.subscribe(to: SceneEvents.Update.self, on: nil, componentType: nil) {
      [weak self] event in
      let delta = Float(event.deltaTime)
      MainActor.assumeIsolated { self?.tick(delta) }
    }
  }

  func setSpinning(_ spinning: Bool) { isSpinning = spinning }

  func setRunning(_ running: Bool) { isRunning = running }

  private func tick(_ delta: Float) {
    guard isRunning, isSpinning else { return }
    angle += delta * Self.radiansPerSecond
    turntable.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
  }

  /// Puts `item` on the turntable in place of what was there.
  func show(_ item: ShopItem) async {
    guard item.id != shown else { return }
    shown = item.id
    let entity: Entity?
    if case .furniture = item.look {
      entity = await models.furniture(item)
    } else {
      entity = models.made(item)
    }
    guard shown == item.id, !Task.isCancelled else { return }
    for child in Array(turntable.children) { child.removeFromParent() }
    guard let entity else { return }
    let bounds = entity.visualBounds(relativeTo: nil)
    let longest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
    let scale = longest > 0 ? Self.span / longest : 1
    entity.scale = .one * scale
    entity.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    turntable.addChild(entity)
  }
}
