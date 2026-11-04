import CoreImage
import DesignSystem
import Foundation
import ImageIO
import Metal
import OSLog
import Pet
import PetScene
import RealityKit
import SwiftUI
import UniformTypeIdentifiers

/// Still pictures of the shop's items for its grid. Each is drawn once, off screen, in the room's
/// own matte look, then kept: a few in memory and every one on disk, under the build that drew it,
/// so a later launch reads them rather than drawing again.
///
/// Drawing takes one renderer and the models it shows. Both go once nothing has been asked for a
/// little while, so the shop holds no renderer while it is only being looked at.
@MainActor
final class NookiShopThumbnails {
  struct Key: Hashable {
    let item: ShopItem.ID
    let pixels: Int
  }

  /// The most pixels across a still is drawn at, whatever the card asks for.
  static let largest = 384
  /// How many stills stay in memory; the rest are read back from disk.
  static let kept = 24
  private static let rests = Duration.seconds(4)
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "ShopThumbnails")

  private let folder: URL?
  private let makeStage: @MainActor () -> ThumbnailStage?
  private var images: [Key: CGImage] = [:]
  private var recent: [Key] = []
  private var tail: Task<Void, Never>?
  private var stage: ThumbnailStage?
  private var rest: Task<Void, Never>?

  /// - Parameter folder: Where stills are kept between launches; `nil` keeps them in memory only.
  nonisolated init(
    folder: URL? = NookiShopThumbnails.standardFolder,
    makeStage: @escaping @MainActor () -> ThumbnailStage? = { try? ThumbnailStage() }
  ) {
    self.folder = folder
    self.makeStage = makeStage
  }

  /// The app's caches, in a folder for this build, so a new build's models are drawn afresh.
  nonisolated static var standardFolder: URL? {
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appending(path: "ShopThumbnails/\(build)", directoryHint: .isDirectory)
  }

  /// The still of `item`, `side` points across at `scale`, or `nil` when it cannot be drawn.
  func image(of item: ShopItem, side: CGFloat, scale: CGFloat) async -> CGImage? {
    let pixels = min(Int((side * scale).rounded()), Self.largest)
    guard pixels > 0 else { return nil }
    let key = Key(item: item.id, pixels: pixels)
    if let image = remembered(key) { return image }
    // One still at a time, in the order asked for.
    let before = tail
    let job = Task { @MainActor () -> CGImage? in
      await before?.value
      if let image = self.remembered(key) { return image }
      let made = await self.draw(item, pixels: pixels)
      if let made {
        self.remember(made, as: key)
        self.write(made, as: key)
      }
      return made
    }
    tail = Task { _ = await job.value }
    return await job.value
  }

  private func remembered(_ key: Key) -> CGImage? {
    if let image = images[key] {
      recent.removeAll { $0 == key }
      recent.append(key)
      return image
    }
    guard let image = read(key) else { return nil }
    remember(image, as: key)
    return image
  }

  private func remember(_ image: CGImage, as key: Key) {
    images[key] = image
    recent.removeAll { $0 == key }
    recent.append(key)
    while recent.count > Self.kept {
      images[recent.removeFirst()] = nil
    }
  }

  private func draw(_ item: ShopItem, pixels: Int) async -> CGImage? {
    rest?.cancel()
    defer { restSoon() }
    if case .style(.view(let view?)) = item.look {
      return await ViewThumbnail.draw(view, pixels: pixels)
    }
    if stage == nil { stage = makeStage() }
    guard let stage else { return nil }
    return await stage.draw(item, pixels: pixels)
  }

  /// Lets the renderer and the models go once nothing more has been asked for a while.
  private func restSoon() {
    rest?.cancel()
    rest = Task { @MainActor [weak self] in
      try? await Task.sleep(for: Self.rests)
      guard !Task.isCancelled else { return }
      self?.stage = nil
    }
  }

  var isDrawing: Bool { stage != nil }

  // MARK: - Disk

  private func file(_ key: Key) -> URL? {
    let safe = key.item.replacingOccurrences(of: "/", with: "-")
    return folder?.appending(path: "\(safe)-\(key.pixels).png")
  }

  private func read(_ key: Key) -> CGImage? {
    guard let url = file(key), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  private func write(_ image: CGImage, as key: Key) {
    guard let folder, let url = file(key) else { return }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      Self.log.error("No folder for stills: \(String(describing: error), privacy: .public)")
      return
    }
    guard
      let target = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(target, image, nil)
    CGImageDestinationFinalize(target)
  }
}

/// The off-screen scene a still is drawn in: a warm key light and fill over the room's ambient
/// light, a camera a little above, and the item turned a little towards it.
@MainActor
final class ThumbnailStage {
  private let renderer: RealityRenderer
  private let root = Entity()
  private let lens = PerspectiveCamera()
  private let holder = Entity()
  private let models: NookiShopModels
  private let loadIdolFile: @MainActor () async -> Entity?
  private var idolFile: Entity??
  private let device: MTLDevice
  private let images: CIContext

  /// The longest side of whatever is shown, in metres.
  private static let span: Float = 0.5
  /// Turned this far to show a side as well as the front.
  private static let turn: Float = 0.5

  init(
    models: NookiShopModels? = nil,
    loadIdolFile: @escaping @MainActor () async -> Entity? = {
      await NookiAssets.compiled(GenzKit.idolFile)
    }
  ) throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw ThumbnailError.noDevice }
    self.device = device
    images = CIContext(mtlDevice: device)
    self.models = models ?? NookiShopModels()
    self.loadIdolFile = loadIdolFile
    renderer = try RealityRenderer()

    lens.camera.fieldOfViewInDegrees = 30
    lens.camera.near = 0.05
    lens.camera.far = 20
    lens.look(at: [0, 0.2, 0], from: [0, 0.48, 1.2], relativeTo: nil)
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
    root.addChild(holder)

    renderer.entities.append(root)
    renderer.activeCamera = lens
    renderer.lighting.intensityExponent = 1
    renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 0))
  }

  private static var warm: RealityKit.Material.Color {
    let swatch = Palette.lightWarm
    return .init(
      red: CGFloat(swatch.red) / 255, green: CGFloat(swatch.green) / 255,
      blue: CGFloat(swatch.blue) / 255, alpha: 1)
  }

  private var hasAmbient = false

  func draw(_ item: ShopItem, pixels: Int) async -> CGImage? {
    if !hasAmbient {
      hasAmbient = true
      if let ambient = await SceneParts.ambientEnvironment() { renderer.lighting.resource = ambient }
    }
    guard let entity = await model(item) else { return nil }
    for child in Array(holder.children) { child.removeFromParent() }
    let bounds = entity.visualBounds(relativeTo: nil)
    let longest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
    let scale = longest > 0 ? Self.span / longest : 1
    entity.scale = .one * scale
    entity.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
    holder.addChild(entity)
    let hangs = if case .furniture(_, _, _, .wall) = item.look { true } else { false }
    holder.orientation = simd_quatf(angle: hangs ? 0 : Self.turn, axis: [0, 1, 0])
    defer { entity.removeFromParent() }
    return await render(pixels: pixels)
  }

  private func model(_ item: ShopItem) async -> Entity? {
    if let prop = GenzPiece.Kind(shopItem: item.id)?.idol {
      if idolFile == nil { idolFile = .some(await loadIdolFile()) }
      guard let file = idolFile ?? nil, let model = file.findEntity(named: prop.modelName) else {
        return nil
      }
      let holder = Entity()
      holder.addChild(GenzKit.matte(model.clone(recursive: true), glows: prop.glows))
      return holder
    }
    if case .furniture = item.look { return await models.furniture(item) }
    return models.made(item)
  }

  private func render(pixels: Int) async -> CGImage? {
    let description = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm_srgb, width: pixels, height: pixels, mipmapped: false)
    description.usage = [.renderTarget, .shaderRead, .shaderWrite]
    description.storageMode = .private
    guard let texture = device.makeTexture(descriptor: description) else { return nil }
    do {
      let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
      // The first frames after a model arrives can miss its textures, so a few are drawn and the
      // last is kept.
      for _ in 0..<Self.frames {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
          do {
            try renderer.updateAndRender(deltaTime: 1 / 30, cameraOutput: output) { _ in
              done.resume()
            }
          } catch {
            done.resume()
          }
        }
      }
    } catch {
      return nil
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard let picture = CIImage(mtlTexture: texture, options: [.colorSpace: space]) else {
      return nil
    }
    // Metal's rows run top down and Core Image's bottom up.
    let upright = picture.oriented(.downMirrored)
    return images.createCGImage(upright, from: upright.extent, format: .RGBA8, colorSpace: space)
  }

  private static let frames = 3
}

enum ThumbnailError: Error {
  case noDevice
}

/// A window view's still: its sky and planes, painted at once, filling the square.
@MainActor
enum ViewThumbnail {
  static func draw(_ view: WindowView, pixels: Int) async -> CGImage? {
    let side = CGFloat(pixels) / 2
    let corners = [
      CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0), CGPoint(x: side, y: side),
      CGPoint(x: 0, y: side),
    ]
    let state = WindowViewState(
      view: view, weather: view.weather, hour: view.hour, time: 30, now: 1_000,
      window: corners, home: corners, lampOn: true)
    let plates = ViewPlateCache()
    let content = NativeWindowView(state: state, plates: plates)
      .frame(width: side, height: side)
      .environment(\.displayScale, 2)
    // The first pass asks for the plates; they are painted on the next turns of the main actor.
    _ = snapshot(content, side: side)
    let deadline = ContinuousClock.now + .seconds(3)
    while !plates.isIdle, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(16))
    }
    return snapshot(content, side: side)
  }

  private static func snapshot(_ content: some View, side: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    renderer.proposedSize = ProposedViewSize(width: side, height: side)
    return renderer.cgImage
  }
}
