import CoreGraphics
import Foundation
import Pet
import RealityKit

/// The lights a lighting preset adds to a styled room: strings of fairy lights with light spilling
/// onto the walls near them, a rim light behind the cat, a low sun through the window, and soft
/// shadows under the furniture and the cat. Everything sits under one entity, gone when the
/// lighting is off.
@MainActor
final class GenzGlow {
  let root = Entity()
  private let layout: GenzLayout
  private var bulbs: [ModelEntity] = []
  /// Where each fairy light hangs, in the room.
  private(set) var bulbPoints: [GenzRoomPoint] = []
  private var spills: [Entity] = []
  private var shadows: [ModelEntity] = []
  /// The furniture's shadows: the piece's index in the layout, and the shadow's height.
  private(set) var pieceShadows: [(index: Int, shadow: ModelEntity, height: Float)] = []
  private let fairy = Entity()
  private let rim = Entity()
  private let sun = Entity()
  private let core = Entity()
  private(set) var look = LightingLook.off

  /// The fairy lights' colour, a warm filament white.
  static let bulbColour = GenzColour(0xFFD58A)
  static let bulbRadius: Float = 0.06
  static let wireThickness: Float = 0.012
  static let bulbSpacing: Float = 0.34
  /// How bright the light a string spills onto the walls is, at full spill, and how far it
  /// reaches.
  static let spillIntensity: Float = 7_800
  static let spillReach: Float = 4.5
  /// How far a string droops between two hooks.
  static let sag: Float = 0.28
  /// How dark a contact shadow is made before a preset sets it.
  static let shadowDarkness: Float = 0.5

  private let kit: GenzKit

  init(layout: GenzLayout, kit: GenzKit) {
    self.layout = layout
    self.kit = kit
    root.name = "genz-glow"
    root.isEnabled = false
    root.addChild(fairy)
    buildFairyLights(kit)
    buildShadows()
    buildRim()
    buildSun()
    buildCore()
  }

  /// The hooks Window Seat's strings of fairy lights hang from, in order.
  static var seatFairyHooks: [[GenzRoomPoint]] {
    let top: Float = 5.22
    let back = stride(from: Float(0.25), through: 7.4, by: 1.43).map {
      GenzRoomPoint($0, 0.08, top)
    }
    let side = stride(from: Float(0.3), through: 5.8, by: 1.375).map {
      GenzRoomPoint(0.08, $0, top)
    }
    return [back, side]
  }

  /// Points along a string hung from `hooks`, about `spacing` apart, drooping by `sag` between
  /// each pair of hooks.
  static func string(_ hooks: [GenzRoomPoint], spacing: Float, sag: Float) -> [GenzRoomPoint] {
    var points: [GenzRoomPoint] = []
    for (start, end) in zip(hooks, hooks.dropFirst()) {
      let length = simd_distance(start.scene, end.scene)
      let count = max(Int((length / spacing).rounded()), 1)
      for step in 0..<count {
        let along = Float(step) / Float(count)
        let droop = sag * 4 * along * (1 - along)
        points.append(
          GenzRoomPoint(
            start.x + (end.x - start.x) * along, start.y + (end.y - start.y) * along,
            start.z + (end.z - start.z) * along - droop))
      }
    }
    if let last = hooks.last { points.append(last) }
    return points
  }

  /// Lights the room as `look` says.
  func apply(_ look: LightingLook) {
    guard look != self.look else { return }
    self.look = look
    root.isEnabled = look.isLit
    // The shadows follow their pieces and the cat, outside the root, so they are shaded here.
    shade(shadows)
    guard look.isLit else { return }
    fairy.isEnabled = look.fairy.shown
    let bulbColour = look.fairy.colour.genz
    for bulb in bulbs { bulb.model?.materials = [kit.glow(bulbColour)] }
    for spill in spills {
      spill.components[PointLightComponent.self]?.color = bulbColour.platformColour
      spill.setLight(intensity: Self.spillIntensity * look.fairy.spill)
    }
    core.components[PointLightComponent.self]?.color = look.key.colour.genz.platformColour
    core.setLight(intensity: look.core)
    rim.components[SpotLightComponent.self]?.color = look.rim.colour.genz.platformColour
    rim.setLight(intensity: look.rim.intensity)
    sun.isEnabled = look.sun.intensity > 0
    sun.components[DirectionalLightComponent.self]?.color = look.sun.colour.genz.platformColour
    sun.setLight(intensity: look.sun.intensity)
  }

  private func shade(_ shadows: [ModelEntity]) {
    for shadow in shadows {
      shadow.isEnabled = look.shadows > 0
      guard var material = shadow.model?.materials.first as? UnlitMaterial else { continue }
      material.blending = .transparent(opacity: .init(floatLiteral: look.shadows))
      shadow.model?.materials = [material]
    }
  }

  /// Puts a soft shadow under the cat, inside `holder`, so it follows the cat about. It is a
  /// `length` square: the room scales it to the cat's pose and keeps it on the seat.
  @discardableResult
  func shadeCat(in holder: Entity, length: Float) -> ModelEntity? {
    guard let shadow = Self.shadow(width: length, depth: length) else { return nil }
    shadow.position = [0, 0.015, 0]
    shadow.scale = [0.64, 1, 0.64]
    holder.addChild(shadow)
    shadows.append(shadow)
    shade([shadow])
    return shadow
  }

  /// Builds each string as two models, its bulbs and its wire, so a string costs the renderer two
  /// draws rather than one for every bulb and every length of wire.
  private func buildFairyLights(_ kit: GenzKit) {
    let bulbMesh = LowPoly.sphere(radius: Self.bulbRadius)
    let bulbMaterial = kit.glow(Self.bulbColour)
    let wire = kit.matte(GenzColour(0x2B2622))
    for (number, hooks) in layout.fairyHooks.enumerated() {
      let points = Self.string(hooks, spacing: Self.bulbSpacing, sag: Self.sag)
      bulbPoints += points
      let strand = Entity()
      fairy.addChild(strand)
      var lamps: [ModelEntity] = []
      for point in points {
        let bulb = ModelEntity(mesh: bulbMesh, materials: [bulbMaterial])
        // Hung just under the wire, so its top never shares a plane with the wire's.
        bulb.position = point.scene + [0, -Self.bulbRadius - Self.wireThickness, 0]
        strand.addChild(bulb)
        lamps.append(bulb)
      }
      for (from, to) in zip(points, points.dropFirst()) {
        let start = from.scene
        let end = to.scene
        let length = simd_distance(start, end)
        guard length > 0 else { continue }
        let segment = kit.part(
          kit.box([Self.wireThickness, Self.wireThickness, length]), wire, at: (start + end) / 2,
          turn: simd_quatf(from: [0, 0, 1], to: simd_normalize(end - start)))
        strand.addChild(segment)
      }
      kit.merge(strand, key: "fairy wire \(number)")
      if let mesh = GenzKit.joined(lamps, in: strand) {
        let joined = ModelEntity(mesh: mesh, materials: [bulbMaterial])
        strand.addChild(joined)
        for lamp in lamps { lamp.removeFromParent() }
        bulbs.append(joined)
      } else {
        bulbs += lamps
      }
      // One light for the whole string, in its middle, as bright as the three it stands for.
      let spill = Entity()
      spill.position = points[points.count / 2].scene + [0, -0.4, 0.35]
      spill.components.set(
        PointLightComponent(
          color: Self.bulbColour.platformColour, intensity: 0,
          attenuationRadius: Self.spillReach))
      fairy.addChild(spill)
      spills.append(spill)
    }
  }

  private func buildShadows() {
    for (index, placement) in layout.pieces.enumerated() {
      let size = placement.piece.kind.size
      // Flat pieces lie on the floor, and pieces stood on others are shaded by what is below.
      guard size.z > 0.1, placement.centre.z < 0.05 else { continue }
      guard let shadow = Self.shadow(width: size.x * 1.08 + 0.5, depth: size.y * 1.08 + 0.5)
      else { continue }
      let height = Self.shadowHeight(pieceShadows.count)
      shadow.position = GenzRoomPoint(placement.centre.x, placement.centre.y, height).scene
      shadow.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
      root.addChild(shadow)
      shadows.append(shadow)
      pieceShadows.append((index, shadow, height))
    }
  }

  /// How high the `order`th furniture shadow lies. Each lies at its own height, so two that
  /// overlap never share a plane, and all stay under the rugs' lowest ring.
  static func shadowHeight(_ order: Int) -> Float {
    min(0.008 + 0.0008 * Float(order), 0.018)
  }

  /// Hands each furniture shadow to the holder of its piece, so it follows the piece when the
  /// piece is moved or turned. `holders` are in the layout's order.
  func follow(_ holders: [Entity]) {
    for (index, shadow, height) in pieceShadows where holders.indices.contains(index) {
      shadow.setParent(holders[index])
      shadow.transform = Transform(translation: [0, height, 0])
    }
    groundShadows()
    shade(shadows)
  }

  /// Keeps each furniture shadow on the floor while its piece is lifted.
  func groundShadows() {
    for (_, shadow, height) in pieceShadows {
      shadow.position.y = height - (shadow.parent?.position.y ?? 0)
    }
  }

  private func buildRim() {
    let spot = layout.cat.spot
    let length = layout.cat.length
    let target = GenzRoomPoint(spot.x, spot.y, spot.z + length * 0.3).scene
    rim.components.set(
      SpotLightComponent(
        color: GenzColour(0xFFB86A).platformColour, intensity: 0, innerAngleInDegrees: 12,
        outerAngleInDegrees: 30, attenuationRadius: 9))
    rim.look(
      at: target, from: GenzRoomPoint(spot.x + 0.8, spot.y - 2.2, spot.z + 3).scene, relativeTo: nil
    )
    root.addChild(rim)
  }

  /// Where the light pools on the floor: the rug, or the middle of the floor without one.
  static func pool(_ layout: GenzLayout) -> GenzRoomPoint {
    let rug = layout.pieces.first { $0.piece.kind == .roundRug }
    return rug?.centre ?? GenzRoomPoint(3.7, 4, 0)
  }

  /// The lantern's light: low over the rug, reaching every wall.
  private func buildCore() {
    let pool = Self.pool(layout)
    core.position = GenzRoomPoint(pool.x, pool.y, 1.4).scene
    core.components.set(PointLightComponent(color: .white, intensity: 0, attenuationRadius: 9))
    root.addChild(core)
  }

  /// A low sun coming in through the window side of the room, casting long shadows.
  private func buildSun() {
    sun.components.set(DirectionalLightComponent(color: .white, intensity: 0))
    sun.components.set(
      DirectionalLightComponent.Shadow(maximumDistance: 16, depthBias: 2))
    let middle = GenzRoomPoint(4, 3, 0.5).scene
    let from = layout.sunFrom.scene
    sun.look(at: middle, from: from, relativeTo: nil)
    sun.isEnabled = false
    root.addChild(sun)
  }

  /// A dark patch, soft at the edges, lying flat on whatever is under it.
  static func shadow(width: Float, depth: Float) -> ModelEntity? {
    guard let texture = shadowTexture else { return nil }
    var material = UnlitMaterial()
    material.color = .init(tint: .black, texture: .init(texture))
    material.blending = .transparent(opacity: .init(floatLiteral: shadowDarkness))
    let patch = ModelEntity(
      mesh: .generatePlane(width: width, depth: depth, cornerRadius: 0), materials: [material])
    patch.name = "genz-shadow"
    return patch
  }

  /// A round falloff from opaque in the middle to clear at the edge, shared by every shadow.
  private static let shadowTexture: TextureResource? = {
    guard let image = falloff(pixels: 64) else { return nil }
    return try? TextureResource(image: image, options: .init(semantic: .color))
  }()

  /// The falloff image: alpha 1 in the middle, easing to 0 at the edge of the square.
  static func falloff(pixels: Int) -> CGImage? {
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let steps = 8
    var colours: [CGColor] = []
    var locations: [CGFloat] = []
    for step in 0...steps {
      let along = CGFloat(step) / CGFloat(steps)
      let alpha = pow(1 - along, 1.8)
      colours.append(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
      locations.append(along)
    }
    guard
      let gradient = CGGradient(
        colorsSpace: space, colors: colours as CFArray, locations: locations)
    else { return nil }
    let middle = CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
    context.drawRadialGradient(
      gradient, startCenter: middle, startRadius: 0, endCenter: middle,
      endRadius: CGFloat(pixels) / 2, options: [])
    return context.makeImage()
  }
}
