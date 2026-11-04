import Foundation
import Pet
import RealityKit
import os

/// The night street outside the window in 3D: a world of its own, seen only through a portal
/// that fills the window's opening, so it never shows past the walls.
///
/// The street is made by `scripts/make_street_view.py`: one mesh of everything that stands still,
/// one of a car, both on one baked atlas, and the far cards with the lamps' glows, the stars and
/// the night sky behind it all on a second texture. The portal draws nothing where the street has
/// nothing, so the sky is the street's own. Everything is unlit, so it adds no real-time light:
/// four draws with the portal.
///
/// It is laid out in the view's own frame: x right, y up, and minus z out from the camera's home
/// place through the window's middle, so at home it is seen straight on, as the flat views are,
/// and any orbit shows it with true depth.
@MainActor
final class Street3D {
  /// The street's meshes and textures, read once and shared by every room that shows it.
  struct Assets {
    var street: MeshResource
    var car: MeshResource
    var cards: MeshResource
    var atlas: TextureResource
    var cardTexture: TextureResource
    var triangles: Int
  }

  /// The lanes the passing car drives in, in units out from the window: nearer going right.
  static let lanes: (right: Float, left: Float) = (32.6, 37.4)
  /// How far along the street a pass runs, either side of the window's middle.
  static let passReach: Float = 80
  static let portalName = "street-3d-portal"

  let root = Entity()
  private let world = Entity()
  private let portal = ModelEntity()
  private let car = ModelEntity()
  private let cars = SuburbNight.cars

  /// Whether a car is passing now.
  var isCarShown: Bool { car.isEnabled }

  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "Street3D")

  init(assets: Assets) {
    world.components.set(WorldComponent())
    var atlas = UnlitMaterial()
    atlas.color = .init(tint: .white, texture: .init(assets.atlas))
    var cards = UnlitMaterial()
    cards.color = .init(tint: .white, texture: .init(assets.cardTexture))
    cards.blending = .transparent(opacity: .init(scale: 1))
    let street = ModelEntity(mesh: assets.street, materials: [atlas])
    let far = ModelEntity(mesh: assets.cards, materials: [cards])
    car.model = ModelComponent(mesh: assets.car, materials: [atlas])
    car.isEnabled = false
    world.addChild(street)
    world.addChild(far)
    world.addChild(car)
    portal.name = Self.portalName
    portal.components.set(PortalComponent(target: world))
    root.addChild(world)
    root.addChild(portal)
  }

  /// Fits the portal to `window`, the opening's four corners in the room, and turns the street to
  /// face `eye`, the camera at its home place.
  func place(window: [SIMD3<Float>], eye: SIMD3<Float>) {
    guard window.count == 4 else { return }
    let xs = window.map(\.x)
    let ys = window.map(\.y)
    let (x0, x1) = (xs.min() ?? 0, xs.max() ?? 0)
    let (y0, y1) = (ys.min() ?? 0, ys.max() ?? 0)
    let wall = window.map(\.z).reduce(0, +) / 4
    // A shade bigger than the opening, and a hair outside the wall, so its edges hide in the
    // wall's thickness rather than leave a seam.
    let margin: Float = 0.08
    portal.model = ModelComponent(
      mesh: .generatePlane(width: x1 - x0 + margin * 2, height: y1 - y0 + margin * 2),
      materials: [PortalMaterial()])
    portal.position = [(x0 + x1) / 2, (y0 + y1) / 2, wall - 0.01]
    let origin = SIMD3<Float>((x0 + x1) / 2, (y0 + y1) / 2, wall)
    world.transform = Transform(matrix: Self.frame(origin: origin, eye: eye))
  }

  /// The view's frame: its origin at `origin`, out along the line from `eye`, up as near the
  /// room's up as that allows.
  static func frame(origin: SIMD3<Float>, eye: SIMD3<Float>) -> simd_float4x4 {
    let out = simd_normalize(origin - eye)
    let up = simd_normalize(SIMD3<Float>(0, 1, 0) - out * out.y)
    let right = simd_cross(out, up)
    return simd_float4x4(
      SIMD4(right, 0), SIMD4(up, 0), SIMD4(-out, 0), SIMD4(origin, 1))
  }

  /// Moves the passing car to where it is at `now`, on the same rhythm as the flat view's cars,
  /// so the cat's head and the headlights on the room still follow it.
  func update(now: Double, reduceMotion: Bool) {
    guard !reduceMotion, let pass = cars.pass(at: now) else {
      if car.isEnabled { car.isEnabled = false }
      return
    }
    let rightward = pass.variant < 0.5
    let progress = Float(pass.progress)
    let x = (rightward ? -1 + 2 * progress : 1 - 2 * progress) * Self.passReach
    let lane = rightward ? Self.lanes.right : Self.lanes.left
    car.position = [x, 0, -lane]
    car.orientation = simd_quatf(angle: rightward ? 0 : .pi, axis: [0, 1, 0])
    if !car.isEnabled { car.isEnabled = true }
  }

  // MARK: - Loading

  private static var loading: Task<Assets?, Never>?

  /// The street's assets, read from the bundle the first time they are asked for.
  static func assets() async -> Assets? {
    if let loading { return await loading.value }
    let task = Task { @MainActor in await load() }
    loading = task
    return await task.value
  }

  private static func load() async -> Assets? {
    guard
      let folder = Bundle.module.url(forResource: "StreetView", withExtension: nil),
      let data = try? Data(contentsOf: folder.appending(path: "street.bin"))
    else {
      log.error("No street view in the bundle")
      return nil
    }
    do {
      let meshes = try StreetMeshFile(data)
      func mesh(_ name: String) async throws -> MeshResource {
        guard let part = meshes.parts[name] else { throw StreetMeshFile.Failure.missing(name) }
        var descriptor = MeshDescriptor(name: "street-\(name)")
        descriptor.positions = MeshBuffer(part.positions)
        descriptor.textureCoordinates = MeshBuffer(part.uvs)
        descriptor.primitives = .triangles(part.indices)
        return try await MeshResource(from: [descriptor])
      }
      let options = TextureResource.CreateOptions(semantic: .color)
      let atlas = try await TextureResource(
        contentsOf: folder.appending(path: "street-atlas.png"), options: options)
      let cards = try await TextureResource(
        contentsOf: folder.appending(path: "street-cards.png"), options: options)
      return Assets(
        street: try await mesh("street"), car: try await mesh("car"),
        cards: try await mesh("cards"), atlas: atlas, cardTexture: cards,
        triangles: meshes.parts.values.map { $0.indices.count / 3 }.reduce(0, +))
    } catch {
      log.error("The street view did not load: \(String(describing: error), privacy: .public)")
      return nil
    }
  }
}

/// `street.bin`, as `make_street_view.py` writes it: `BSV1`, a mesh count, then per mesh a name
/// (a byte of length and UTF-8), vertex and index counts (u32), vertices as x y z u v (f32) and
/// u16 indices. Little-endian throughout. v counts down from the image's top row; RealityKit's
/// counts up from its bottom, so it is turned over as it is read.
struct StreetMeshFile {
  struct Part {
    var positions: [SIMD3<Float>]
    var uvs: [SIMD2<Float>]
    var indices: [UInt32]
  }

  enum Failure: Error {
    case notAStreet
    case short
    case missing(String)
  }

  var parts: [String: Part] = [:]

  init(_ data: Data) throws(Failure) {
    let bytes = [UInt8](data)
    var at = 0
    func take(_ count: Int) throws(Failure) -> ArraySlice<UInt8> {
      guard at + count <= bytes.count else { throw .short }
      defer { at += count }
      return bytes[at..<(at + count)]
    }
    func u32() throws(Failure) -> UInt32 {
      let raw = try take(4)
      return raw.reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
    func u16() throws(Failure) -> UInt16 {
      let raw = try take(2)
      return UInt16(raw[raw.startIndex]) | UInt16(raw[raw.startIndex + 1]) << 8
    }
    func f32() throws(Failure) -> Float { Float(bitPattern: try u32()) }

    guard Array(try take(4)) == Array("BSV1".utf8) else { throw .notAStreet }
    let count = try u32()
    for _ in 0..<count {
      let length = Int(try take(1).first ?? 0)
      let name = String(decoding: try take(length), as: UTF8.self)
      let vertices = Int(try u32())
      let indexCount = Int(try u32())
      var part = Part(positions: [], uvs: [], indices: [])
      part.positions.reserveCapacity(vertices)
      part.uvs.reserveCapacity(vertices)
      for _ in 0..<vertices {
        part.positions.append(SIMD3(try f32(), try f32(), try f32()))
        let (u, v) = (try f32(), try f32())
        part.uvs.append(SIMD2(u, 1 - v))
      }
      part.indices.reserveCapacity(indexCount)
      for _ in 0..<indexCount { part.indices.append(UInt32(try u16())) }
      parts[name] = part
    }
  }
}
