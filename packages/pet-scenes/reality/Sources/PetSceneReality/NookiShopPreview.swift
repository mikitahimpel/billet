import DesignSystem
import Metal
import Pet
import QuartzCore
import RealityKit
import SwiftUI

/// The one live preview the shop shows. It keeps a single scene and swaps the item in it, so
/// moving from card to card never starts another renderer.
///
/// It draws off screen rather than through a RealityView: a RealityView mounted while another
/// exists, or just after one went, can stay empty for good while its scene keeps updating, and the
/// room behind the shop is one. The flat glyph stays until a frame with the item has been drawn.
struct NookiShopPreview: View {
  let item: ShopItem

  @State private var stage = NookiPreviewStage()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    ZStack {
      NookiTurntableView(stage: stage)
      if stage.presented != item.id { ShopItemGlyph(item: item) }
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
@Observable
final class NookiPreviewStage {
  let root = Entity()
  private let lens = PerspectiveCamera()
  private let turntable = Entity()
  private let models: NookiShopModels
  @ObservationIgnored private var renderer: RealityRenderer?
  @ObservationIgnored private var isDrawing = false
  /// The item asked for last. Loading it can be cancelled, so this is not what is on the table.
  private var wanted: ShopItem.ID?
  private(set) var onTable: ShopItem.ID?
  /// The item in the last frame drawn. The renderer takes seconds to start, and the card shows the
  /// flat glyph until then.
  private(set) var presented: ShopItem.ID?
  private var angle: Float = 0.5
  private var isSpinning = true
  private var isRunning = true

  private static let radiansPerSecond: Float = 0.9
  /// Off screen there is no default light, so the preview uses the room's, a little brighter.
  private static let ambientExponent: Float = 1
  /// The longest side of whatever is shown, in metres.
  private static let span: Float = 0.5

  init(models: NookiShopModels? = nil) {
    self.models = models ?? NookiShopModels()
    lens.camera.fieldOfViewInDegrees = 30
    // The item stands about a metre and a quarter away, so these keep the depth fine.
    lens.camera.near = 0.05
    lens.camera.far = 20
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

  func setSpinning(_ spinning: Bool) { isSpinning = spinning }

  func setRunning(_ running: Bool) { isRunning = running }

  /// Turns the table and draws one frame into `layer`, unless the last is still being drawn.
  func draw(into layer: CAMetalLayer, delta: Float) {
    guard isRunning, !isDrawing, let drawable = layer.nextDrawable() else { return }
    if isSpinning {
      angle += delta * Self.radiansPerSecond
      turntable.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
    }
    do {
      let renderer = try activeRenderer()
      let output = try RealityRenderer.CameraOutput(
        .singleProjection(colorTexture: drawable.texture))
      let item = onTable
      isDrawing = true
      nonisolated(unsafe) let finished = drawable
      try renderer.updateAndRender(deltaTime: TimeInterval(delta), cameraOutput: output) {
        [weak self] _ in
        finished.present()
        Task { @MainActor in self?.frameDrawn(item) }
      }
    } catch {
      isDrawing = false
    }
  }

  private func frameDrawn(_ item: ShopItem.ID?) {
    isDrawing = false
    if presented != item { presented = item }
  }

  private func activeRenderer() throws -> RealityRenderer {
    if let renderer { return renderer }
    let made = try RealityRenderer()
    made.entities.append(root)
    made.activeCamera = lens
    made.lighting.intensityExponent = Self.ambientExponent
    Task { [weak made] in
      if let ambient = await SceneParts.ambientEnvironment() { made?.lighting.resource = ambient }
    }
    made.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
    renderer = made
    return made
  }

  /// Puts `item` on the turntable in place of what was there.
  func show(_ item: ShopItem) async {
    wanted = item.id
    guard item.id != onTable else { return }
    onTable = nil
    for child in Array(turntable.children) { child.removeFromParent() }
    let entity: Entity?
    if case .furniture = item.look {
      entity = await models.furniture(item)
    } else {
      entity = models.made(item)
    }
    guard wanted == item.id, !Task.isCancelled, let entity else { return }
    for child in Array(turntable.children) { child.removeFromParent() }
    let bounds = entity.visualBounds(relativeTo: nil)
    let longest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
    let scale = longest > 0 ? Self.span / longest : 1
    entity.scale = .one * scale
    entity.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    turntable.addChild(entity)
    onTable = item.id
  }
}

#if canImport(UIKit)
  /// Hosts the layer the stage draws into, and paces the frames while it is in a window.
  private struct NookiTurntableView: UIViewRepresentable {
    let stage: NookiPreviewStage

    func makeUIView(context: Context) -> NookiTurntableLayerView {
      NookiTurntableLayerView(stage: stage)
    }

    func updateUIView(_ view: NookiTurntableLayerView, context: Context) {}
  }

  private final class NookiTurntableLayerView: UIView {
    private static let framesPerSecond: Float = 30

    private let stage: NookiPreviewStage
    private var pace: CADisplayLink?

    override class var layerClass: AnyClass { CAMetalLayer.self }

    private var metalLayer: CAMetalLayer {
      guard let layer = layer as? CAMetalLayer else {
        preconditionFailure("layerClass is CAMetalLayer")
      }
      return layer
    }

    init(stage: NookiPreviewStage) {
      self.stage = stage
      super.init(frame: .zero)
      isOpaque = false
      backgroundColor = .clear
      metalLayer.device = MTLCreateSystemDefaultDevice()
      metalLayer.pixelFormat = .bgra8Unorm_srgb
      metalLayer.framebufferOnly = false
      metalLayer.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("not made from a coder")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      let scale = window?.screen.scale ?? traitCollection.displayScale
      metalLayer.drawableSize = CGSize(
        width: bounds.width * scale, height: bounds.height * scale)
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      pace?.invalidate()
      pace = nil
      guard window != nil else { return }
      let link = CADisplayLink(target: self, selector: #selector(step))
      link.preferredFrameRateRange = CAFrameRateRange(
        minimum: Self.framesPerSecond, maximum: Self.framesPerSecond)
      link.add(to: .main, forMode: .common)
      pace = link
    }

    @objc private func step(_ link: CADisplayLink) {
      guard bounds.width > 0, bounds.height > 0 else { return }
      stage.draw(into: metalLayer, delta: Float(link.targetTimestamp - link.timestamp))
    }
  }
#else
  private struct NookiTurntableView: View {
    let stage: NookiPreviewStage

    var body: some View { Color.clear }
  }
#endif
