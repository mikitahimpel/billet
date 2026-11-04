import CoreGraphics
import Foundation
import Pet
import RealityKit

/// Dresses the Window Seat as its ``RoomStyle`` says: a skin of paint or wallpaper just in front
/// of the back and side walls, another over the floor, and curtains in the window's recess.
///
/// The room's own walls stay as they are underneath, so the standard style hides the wall skins.
/// The floor skin is always drawn, at the floor line, over the shell's floor dropped just below
/// it: a skin above the floor line would share a plane with the rugs and the cat's shadow.
///
/// Each skin is one mesh with its texture laid in room units, so a pattern runs on across the
/// strips of wall around the window without a seam. Patterns are drawn in code, 256 pixels
/// square and tiling, once each and only when first shown.
@MainActor
final class GenzRoomStyler {
  static let wallName = "genz-style-wall"
  static let sideName = "genz-style-side"
  static let floorName = "genz-style-floor"
  static let curtainName = "genz-style-curtain"

  /// How far below the floor line the room's own floor sits, under the floor skin.
  static let floorDrop: Float = 0.01
  /// How far a skin stands in front of the wall it covers.
  static let lift: Float = 0.008
  /// How long the curtains take to draw from open to closed.
  static let drawLength: Float = 0.7

  let root = Entity()
  private let kit: GenzKit
  private let wall = ModelEntity()
  private let side = ModelEntity()
  private let floor = ModelEntity()
  private let curtains = Entity()
  private let panels = (left: ModelEntity(), right: ModelEntity())
  private var textures: [GenzStylePattern: TextureResource] = [:]
  private var making: Set<GenzStylePattern> = []
  /// Patterns that could not be drawn, shown as their plain colour instead.
  private var failed: Set<GenzStylePattern> = []

  private(set) var style = RoomStyle.standard
  /// How much of the window the curtains cover now, from 0 to 1, moving towards the style's.
  private(set) var cover = Float(CurtainDrape.standard.cover)

  init(kit: GenzKit) {
    self.kit = kit
    root.name = "genz-style"
    wall.name = Self.wallName
    side.name = Self.sideName
    floor.name = Self.floorName
    curtains.name = Self.curtainName
    let seat = GenzLayout.Seat.self
    wall.model = ModelComponent(
      mesh: Self.backWall(), materials: [kit.matte(GenzColour(0x1A2436))])
    side.model = ModelComponent(
      mesh: Self.sideWall(), materials: [kit.matte(GenzColour(0x141D2C))])
    floor.model = ModelComponent(
      mesh: Self.floorSkin(), materials: [kit.matte(GenzColour(RoomFloor.plain.colour))])
    let height = seat.window.z1 - seat.window.z0 + 0.03
    let mesh = Self.pleats(height: height, depth: Self.pleatDepth)
    for panel in [panels.left, panels.right] {
      panel.model = ModelComponent(mesh: mesh, materials: [kit.matte(GenzColour(0xE6DAC4))])
      curtains.addChild(panel)
    }
    let rodLength = seat.window.x1 - seat.window.x0 + 0.1
    curtains.addChild(
      kit.part(
        kit.box([rodLength, 0.05, 0.05]), kit.matte(GenzColour(0x3B2A20)),
        at: GenzRoomPoint(
          (seat.window.x0 + seat.window.x1) / 2, Self.curtainY, seat.window.z1 - 0.04
        ).scene))
    for part in [wall, side, floor] { root.addChild(part) }
    root.addChild(curtains)
    wall.isEnabled = false
    side.isEnabled = false
    curtains.isEnabled = false
    placePanels()
  }

  /// Shows `style`. A pattern not yet drawn is drawn first, the surface keeping its last look
  /// until then; the curtains then draw to the new cover over ``drawLength`` unless `animated`
  /// is false.
  func apply(_ style: RoomStyle, animated: Bool) {
    self.style = style
    dress()
    if !animated {
      cover = Float(style.drape.cover)
      placePanels()
    }
  }

  /// Moves the curtains a frame towards where the style has them.
  func step(_ delta: Float) {
    let target = Float(style.drape.cover)
    guard cover != target else { return }
    let move = delta / Self.drawLength
    cover = abs(target - cover) <= move ? target : cover + (target > cover ? move : -move)
    placePanels()
  }

  // MARK: - Dressing

  private func dress() {
    let wallPattern = style.wall.isWallpaper ? GenzStylePattern.wall(style.wall) : nil
    let floorPattern: GenzStylePattern? =
      switch style.floor {
      case .plain: nil
      case .lightWood, .darkWood, .herringbone, .tiles: .floor(style.floor)
      }
    let fabricPattern: GenzStylePattern? =
      switch style.curtains {
      case .gingham: .gingham(style.curtains.colours.base, style.curtains.colours.pattern ?? 0)
      case .none, .linen, .sheer, .rose, .forest: nil
      }
    let needed = [wallPattern, floorPattern, fabricPattern].compactMap { $0 }
      .filter { textures[$0] == nil && !failed.contains($0) }
    let toMake = needed.filter { !making.contains($0) }
    if !toMake.isEmpty {
      making.formUnion(toMake)
      Task { [weak self] in
        for pattern in toMake { await self?.make(pattern) }
        self?.dress()
      }
    }
    guard needed.isEmpty else { return }
    dressWalls(wallPattern)
    dressFloor(floorPattern)
    dressCurtains(fabricPattern)
  }

  private func make(_ pattern: GenzStylePattern) async {
    defer { making.remove(pattern) }
    guard let image = pattern.image(),
      let texture = try? await TextureResource(image: image, options: .init(semantic: .color))
    else {
      failed.insert(pattern)
      return
    }
    textures[pattern] = texture
  }

  private func dressWalls(_ pattern: GenzStylePattern?) {
    let shown = style.wall != .standard
    wall.isEnabled = shown
    side.isEnabled = shown
    guard shown else { return }
    if let pattern, let texture = textures[pattern] {
      wall.model?.materials = [Self.textured(texture, shade: 1)]
      side.model?.materials = [Self.textured(texture, shade: Self.sideShade)]
    } else {
      let base = GenzColour(style.wall.colours.base)
      wall.model?.materials = [kit.matte(base)]
      side.model?.materials = [kit.matte(base.scaled(Self.sideShade))]
    }
  }

  private func dressFloor(_ pattern: GenzStylePattern?) {
    guard let pattern, let texture = textures[pattern] else {
      floor.model?.materials = [kit.matte(GenzColour(style.floor.colour))]
      return
    }
    var material = Self.textured(texture, shade: 1)
    material.roughness = 0.62
    floor.model?.materials = [material]
  }

  private func dressCurtains(_ pattern: GenzStylePattern?) {
    let fabric = style.curtains
    curtains.isEnabled = fabric != .none
    guard fabric != .none else { return }
    let colour = GenzColour(fabric.colours.base)
    var material: PhysicallyBasedMaterial
    if let pattern, let texture = textures[pattern] {
      material = Self.textured(texture, shade: 1)
    } else if let linen = kit.textures[.linen], fabric == .linen || fabric == .sheer {
      material = kit.matte(colour)
      material.baseColor = .init(tint: colour.platformColour, texture: .init(linen.colour))
      if let normal = linen.normal { material.normal = .init(texture: .init(normal)) }
      material.textureCoordinateTransform = .init(scale: [3, 6])
    } else {
      material = kit.matte(colour)
    }
    switch fabric {
    case .rose, .forest:
      material.roughness = 0.55
      material.sheen = .init(tint: colour.scaled(1.6).platformColour)
    case .sheer:
      material.blending = .transparent(opacity: .init(floatLiteral: 0.55))
    case .none, .linen, .gingham: break
    }
    material.faceCulling = .none
    panels.left.model?.materials = [material]
    panels.right.model?.materials = [material]
  }

  /// How much darker the side wall is than the back wall, as the room's own shell has it.
  static let sideShade: Float = 0.78

  private static func textured(_ texture: TextureResource, shade: Float) -> PhysicallyBasedMaterial
  {
    var material = PhysicallyBasedMaterial()
    material.baseColor = .init(
      tint: .init(red: CGFloat(shade), green: CGFloat(shade), blue: CGFloat(shade), alpha: 1),
      texture: .init(texture))
    material.roughness = 0.9
    material.metallic = 0.0
    return material
  }

  // MARK: - Curtains

  /// How far out from the back wall's face the curtains hang: just inside the glass, so the
  /// note hanging in the window stays in front of them even when they are drawn.
  static let curtainY: Float = -0.158
  /// How deep the pleats are, kept shallow to fit between the glass and the note.
  static let pleatDepth: Float = 0.026
  /// The narrowest a panel gathers to, open.
  static let gathered: Float = 0.5

  /// Each panel's span along the back wall at `cover`, left and right.
  static func panelSpans(cover: Float) -> (left: ClosedRange<Float>, right: ClosedRange<Float>) {
    let window = GenzLayout.Seat.window
    let half = (window.x1 - window.x0) / 2
    let share = min(max(cover, 0), 1)
    // Drawn, the two panels overlap a little in the middle so no light shows between them.
    let width = max(gathered, half * share) + 0.05 + 0.05 * share
    return (
      window.x0 - 0.05...window.x0 - 0.05 + width, window.x1 + 0.05 - width...window.x1 + 0.05
    )
  }

  private func placePanels() {
    let spans = Self.panelSpans(cover: cover)
    let seat = GenzLayout.Seat.self
    // The right panel hangs a touch further back, so where the two overlap they never fight.
    for (panel, span, out) in [
      (panels.left, spans.left, Float(0)), (panels.right, spans.right, Float(-0.006)),
    ] {
      panel.position = GenzRoomPoint(span.lowerBound, Self.curtainY + out, seat.window.z1 + 0.02)
        .scene
      panel.scale = [span.upperBound - span.lowerBound, 1, 1]
    }
  }

  /// A curtain of unit width hanging `height` down from its top, folded into pleats `depth`
  /// deep.
  static func pleats(height: Float, count: Int = 7, depth: Float) -> MeshResource {
    var mesh = GenzUVMesh()
    let steps = count * 2
    func edge(_ index: Int) -> (x: Float, z: Float) {
      (Float(index) / Float(steps), index.isMultiple(of: 2) ? -depth / 2 : depth / 2)
    }
    for index in 0..<steps {
      let a = edge(index)
      let b = edge(index + 1)
      mesh.quad(
        [
          SIMD3(a.x, -height, a.z), SIMD3(b.x, -height, b.z), SIMD3(b.x, 0, b.z),
          SIMD3(a.x, 0, a.z),
        ]
      ) { SIMD2($0.x, -$0.y / height) }
    }
    return mesh.mesh(name: "genz-curtain")
  }

  // MARK: - Skins

  /// How many room units one repeat of a wall's pattern covers.
  static let wallTile: Float = 1.4
  /// How many room units one repeat of a floor's pattern covers.
  static let floorTile: Float = 2.6

  /// The back wall's face around the window, as one mesh.
  static func backWall() -> MeshResource {
    let seat = GenzLayout.Seat.self
    let window = seat.window
    let under = window.z0 - 0.12
    let strips: [(x: ClosedRange<Float>, z: ClosedRange<Float>)] = [
      (0...window.x0, 0...seat.height),
      (window.x1...seat.width, 0...seat.height),
      (window.x0...window.x1, 0...under),
      (window.x0...window.x1, window.z1...seat.height),
    ]
    var mesh = GenzUVMesh()
    for strip in strips {
      let (x, z) = (strip.x, strip.z)
      mesh.quad(
        [
          SIMD3(x.lowerBound, z.lowerBound, lift), SIMD3(x.upperBound, z.lowerBound, lift),
          SIMD3(x.upperBound, z.upperBound, lift), SIMD3(x.lowerBound, z.upperBound, lift),
        ]
      ) { SIMD2($0.x, -$0.y) / wallTile }
    }
    return mesh.mesh(name: "genz-style-wall")
  }

  /// The side wall's face, on the left.
  static func sideWall() -> MeshResource {
    let seat = GenzLayout.Seat.self
    var mesh = GenzUVMesh()
    mesh.quad(
      [
        SIMD3(lift, 0, 0), SIMD3(lift, seat.height, 0), SIMD3(lift, seat.height, seat.depth),
        SIMD3(lift, 0, seat.depth),
      ]
    ) { SIMD2($0.z, -$0.y) / wallTile }
    return mesh.mesh(name: "genz-style-side")
  }

  /// The floor's face, at the floor line.
  static func floorSkin() -> MeshResource {
    let seat = GenzLayout.Seat.self
    var mesh = GenzUVMesh()
    mesh.quad(
      [
        SIMD3(0, 0, 0), SIMD3(0, 0, seat.depth), SIMD3(seat.width, 0, seat.depth),
        SIMD3(seat.width, 0, 0),
      ]
    ) { SIMD2($0.x, $0.z) / floorTile }
    return mesh.mesh(name: "genz-style-floor")
  }
}

/// Flat faces with texture coordinates, collected into one mesh.
struct GenzUVMesh {
  private var positions: [SIMD3<Float>] = []
  private var normals: [SIMD3<Float>] = []
  private var coordinates: [SIMD2<Float>] = []
  private var indices: [UInt32] = []

  /// A flat four-cornered face, wound anticlockwise seen from the side it faces, with each
  /// corner's texture coordinates from `uv`.
  mutating func quad(_ corners: [SIMD3<Float>], uv: (SIMD3<Float>) -> SIMD2<Float>) {
    let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
    let start = UInt32(positions.count)
    positions += corners
    normals += Array(repeating: normal, count: corners.count)
    coordinates += corners.map(uv)
    indices += [start, start + 1, start + 2, start, start + 2, start + 3]
  }

  var triangleCount: Int { indices.count / 3 }

  @MainActor func mesh(name: String) -> MeshResource {
    var descriptor = MeshDescriptor(name: name)
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.textureCoordinates = MeshBuffer(coordinates)
    descriptor.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.01)
  }
}

extension GenzColour {
  init(red: Float, green: Float, blue: Float) {
    let channel = { (value: Float) in UInt32(max(min(value, 1), 0) * 255 + 0.5) }
    self.init(channel(red) << 16 | channel(green) << 8 | channel(blue))
  }

  /// The colour with each channel times `factor`.
  func scaled(_ factor: Float) -> GenzColour {
    GenzColour(red: red * factor, green: green * factor, blue: blue * factor)
  }
}
