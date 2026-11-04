import CoreGraphics
import Foundation
import RealityKit

/// Smooth-shaded meshes for the soft and turned things in the styled rooms: pillows and cushions
/// with a seam round their middle, turned pots and candles, and tubes for wires and sleeves.
/// Unlike ``GenzFaces`` each vertex has its own normal, so fabric and glaze read as soft, and
/// each carries texture coordinates for the knit, linen and wood textures.
struct GenzSmooth {
  private var positions: [SIMD3<Float>] = []
  private var normals: [SIMD3<Float>] = []
  private var coordinates: [SIMD2<Float>] = []
  private var indices: [UInt32] = []

  var triangleCount: Int { indices.count / 3 }

  /// A grid of `columns` by `rows` quads over `point`, which maps (u, v) from 0 to 1 to a
  /// position. Normals come from the surface's slope; `flip` turns the faces round.
  mutating func grid(
    columns: Int, rows: Int, flip: Bool = false, repeats: SIMD2<Float> = [1, 1],
    _ point: (Float, Float) -> SIMD3<Float>
  ) {
    let start = UInt32(positions.count)
    let step: Float = 0.0005
    for row in 0...rows {
      for column in 0...columns {
        let u = Float(column) / Float(columns)
        let v = Float(row) / Float(rows)
        let here = point(u, v)
        let alongU = point(min(u + step, 1), v) - point(max(u - step, 0), v)
        let alongV = point(u, min(v + step, 1)) - point(u, max(v - step, 0))
        var normal = simd_cross(alongU, alongV)
        if flip { normal = -normal }
        let length = simd_length(normal)
        positions.append(here)
        normals.append(length > 1e-9 ? normal / length : [0, 1, 0])
        coordinates.append(SIMD2(u, v) * repeats)
      }
    }
    let width = UInt32(columns + 1)
    for row in 0..<UInt32(rows) {
      for column in 0..<UInt32(columns) {
        let a = start + row * width + column
        let b = a + 1
        let c = a + width
        let d = c + 1
        indices += flip ? [a, c, b, b, c, d] : [a, b, c, b, d, c]
      }
    }
  }

  @MainActor func mesh(_ name: String) -> MeshResource {
    var descriptor = MeshDescriptor(name: name)
    descriptor.positions = MeshBuffer(positions)
    descriptor.normals = MeshBuffer(normals)
    descriptor.textureCoordinates = MeshBuffer(coordinates)
    descriptor.primitives = .triangles(indices)
    return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: 0.01)
  }
}

/// The shape of a stuffed thing such as a pillow or a seat cushion.
struct GenzStuffing: Hashable {
  /// How square it is seen from above: 2 is round-cornered, 8 nearly square.
  var squareness: Float = 3
  /// How flat its top is: 1 domes from the seam, 6 stays flat to near the edge.
  var flatness: Float = 2
  /// How far the middles of its edges are drawn in, as a share of its size.
  var pinch: Float = 0.06
  /// How deep the creases near its corners are, as a share of its thickness.
  var creases: Float = 0.08

  static let pillow = GenzStuffing()
  static let cushion = GenzStuffing(squareness: 10, flatness: 7, pinch: 0.004, creases: 0.02)
  static let pouf = GenzStuffing(squareness: 2, flatness: 3, pinch: 0, creases: 0.05)
  static let cloth = GenzStuffing(squareness: 5, flatness: 1.4, pinch: 0.03, creases: 0.35)
}

@MainActor
extension GenzKit {
  /// Something stuffed, `size` across (x), thick (y) and deep (z), centred on the origin, with a
  /// seam round its middle where its top and bottom meet.
  func stuffed(
    _ size: SIMD3<Float>, _ shape: GenzStuffing = .pillow, repeats: Float = 1, detail: Int = 16
  ) -> MeshResource {
    cached("stuffed \(size) \(shape) \(repeats) \(detail)") {
      var mesh = GenzSmooth()
      let half = size / 2
      for side: Float in [1, -1] {
        mesh.grid(
          columns: detail, rows: max(detail * 3 / 4, 3), flip: side > 0,
          repeats: [repeats, repeats * size.z / size.x]
        ) { u, v in
          let x = u * 2 - 1
          let z = v * 2 - 1
          let ax = pow(abs(x), shape.squareness)
          let az = pow(abs(z), shape.squareness)
          let rise = pow(max((1 - ax) * (1 - az), 0), 1 / shape.flatness)
          let crease = 1 - shape.creases * (1 - rise) * sin(Float.pi * 3 * (x + z)) * 0.5
          let pullX = 1 - shape.pinch * (1 - z * z)
          let pullZ = 1 - shape.pinch * (1 - x * x)
          return [x * half.x * pullX, side * half.y * rise * crease, z * half.z * pullZ]
        }
      }
      return mesh.mesh("stuffed")
    }
  }

  /// A turned shape: `profile` as (radius, height) pairs from the bottom up, swept round the
  /// vertical in `sides` steps, standing on y = 0. Put radius 0 at the ends to close them.
  func lathe(_ name: String, _ profile: [SIMD2<Float>], sides: Int = 24, repeats: Float = 1)
    -> MeshResource
  {
    cached("lathe \(name) \(sides)") {
      var mesh = GenzSmooth()
      let last = Float(profile.count - 1)
      mesh.grid(columns: sides, rows: profile.count - 1, repeats: [repeats, 1]) { u, v in
        let position = v * last
        let index = min(Int(position), profile.count - 2)
        let share = position - Float(index)
        let point = profile[index] * (1 - share) + profile[index + 1] * share
        let angle = u * 2 * .pi
        return [cos(angle) * point.x, point.y, -sin(angle) * point.x]
      }
      return mesh.mesh(name)
    }
  }

  /// A round tube of `radius` along `path`, open at its ends.
  func tube(_ name: String, _ path: [SIMD3<Float>], radius: Float, sides: Int = 8)
    -> MeshResource
  {
    cached("tube \(name) \(radius)") {
      var mesh = GenzSmooth()
      let frames = Self.frames(along: path)
      let last = Float(path.count - 1)
      mesh.grid(columns: sides, rows: path.count - 1) { u, v in
        let position = v * last
        let index = min(Int(position), path.count - 2)
        let share = position - Float(index)
        let centre = path[index] * (1 - share) + path[index + 1] * share
        let frame = frames[share < 0.5 ? index : index + 1]
        let angle = u * 2 * .pi
        return centre + (frame.0 * cos(angle) + frame.1 * sin(angle)) * radius
      }
      return mesh.mesh(name)
    }
  }

  /// A flattened tube along `path`, like a sleeve lying slack: at each point it is `widths` across
  /// and `thicknesses` through, the thin side facing up where it lies flat and out where it hangs.
  /// Open at its ends; a thickness near zero pinches an end shut.
  func flatTube(
    _ name: String, _ path: [SIMD3<Float>], widths: [Float], thicknesses: [Float], sides: Int = 12
  ) -> MeshResource {
    cached("flat tube \(name)") {
      var mesh = GenzSmooth()
      let frames = Self.frames(along: path)
      let last = Float(path.count - 1)
      mesh.grid(columns: sides, rows: path.count - 1) { u, v in
        let position = v * last
        let index = min(Int(position), path.count - 2)
        let share = position - Float(index)
        func blend(_ values: [Float]) -> Float {
          values[index] * (1 - share) + values[index + 1] * share
        }
        let centre: SIMD3<Float> = path[index] * (1 - share) + path[index + 1] * share
        let frame = frames[share < 0.5 ? index : index + 1]
        let angle: Float = u * 2 * .pi
        let through: Float = cos(angle) * blend(thicknesses) / 2
        let across: Float = sin(angle) * blend(widths) / 2
        return centre + frame.0 * through + frame.1 * across
      }
      return mesh.mesh(name)
    }
  }

  /// Two directions across the path at each point, turning as little as possible along it.
  private static func frames(along path: [SIMD3<Float>]) -> [(SIMD3<Float>, SIMD3<Float>)] {
    var frames: [(SIMD3<Float>, SIMD3<Float>)] = []
    var across = SIMD3<Float>(0, 1, 0)
    for index in path.indices {
      let ahead = path[min(index + 1, path.count - 1)] - path[max(index - 1, 0)]
      let tangent = simd_normalize(ahead)
      var side = across - tangent * simd_dot(across, tangent)
      if simd_length(side) < 1e-4 { side = simd_cross(tangent, [1, 0, 0]) }
      side = simd_normalize(side)
      frames.append((side, simd_cross(tangent, side)))
      across = side
    }
    return frames
  }

  /// A curve that hangs between `start` and `end`, sagging `sag` at its middle, in `steps`.
  static func hanging(from start: SIMD3<Float>, to end: SIMD3<Float>, sag: Float, steps: Int = 10)
    -> [SIMD3<Float>]
  {
    (0...steps).map { step in
      let share = Float(step) / Float(steps)
      let dip = 4 * share * (1 - share) * sag
      return start + (end - start) * share - [0, dip, 0]
    }
  }

  /// A box of `size` centred on the origin with its edges rounded to `radius`, in a few hundred
  /// triangles: each face is a small grid whose outer rows bend round onto the next face.
  func softBox(_ size: SIMD3<Float>, radius: Float) -> MeshResource {
    let half = size / 2
    let radius = min(radius, half.min() - 0.0005)
    guard radius > 0.0005 else { return box(size) }
    return cached("soft box \(size) \(radius)") {
      let inner = half - radius
      var positions: [SIMD3<Float>] = []
      var normals: [SIMD3<Float>] = []
      var coordinates: [SIMD2<Float>] = []
      var indices: [UInt32] = []
      func samples(_ axis: Int) -> [Float] {
        let edge = inner[axis]
        let bend = edge + radius * 0.414
        return [-half[axis], -bend, -edge, edge, bend, half[axis]]
      }
      for axis in 0..<3 {
        for sign: Float in [-1, 1] {
          let across = (axis + 1) % 3
          let along = (axis + 2) % 3
          let start = UInt32(positions.count)
          let acrossSamples = samples(across)
          let alongSamples = samples(along)
          for a in alongSamples {
            for b in acrossSamples {
              var point = SIMD3<Float>(repeating: 0)
              point[axis] = sign * half[axis]
              point[across] = b
              point[along] = a
              let core = simd_clamp(point, -inner, inner)
              let out = simd_normalize(point - core)
              positions.append(core + out * radius)
              normals.append(out)
              coordinates.append([b / size[across] + 0.5, a / size[along] + 0.5])
            }
          }
          let width = UInt32(acrossSamples.count)
          for row in 0..<UInt32(alongSamples.count - 1) {
            for column in 0..<(width - 1) {
              let a = start + row * width + column
              let b = a + 1
              let c = a + width
              let d = c + 1
              indices += sign > 0 ? [a, b, d, a, d, c] : [a, d, b, a, c, d]
            }
          }
        }
      }
      var descriptor = MeshDescriptor(name: "soft box")
      descriptor.positions = MeshBuffer(positions)
      descriptor.normals = MeshBuffer(normals)
      descriptor.textureCoordinates = MeshBuffer(coordinates)
      descriptor.primitives = .triangles(indices)
      return (try? MeshResource.generate(from: [descriptor])) ?? .generateBox(size: size)
    }
  }

  /// A ball of `radius` centred on the origin, smooth but light.
  func ball(_ radius: Float) -> MeshResource { beads("ball \(radius)", [.zero], radius: radius) }

  // MARK: - Materials

  /// A glossy glazed ceramic in `colour`.
  func glaze(_ colour: GenzColour) -> PhysicallyBasedMaterial {
    var material = matte(colour)
    material.roughness = 0.32
    material.clearcoat = .init(floatLiteral: 0.7)
    material.clearcoatRoughness = .init(floatLiteral: 0.12)
    return material
  }

  /// A matte material in `colour` with `texture`'s grain, repeated `repeats` times across each
  /// face. Before the textures are made it is plain.
  func matte(_ colour: GenzColour, _ texture: GenzTexture, repeats: SIMD2<Float> = [1, 1])
    -> PhysicallyBasedMaterial
  {
    var material = matte(colour)
    guard let made = textures[texture] else { return material }
    material.baseColor = .init(tint: colour.platformColour, texture: .init(made.colour))
    if let normal = made.normal { material.normal = .init(texture: .init(normal)) }
    material.textureCoordinateTransform = .init(scale: repeats)
    return material
  }

  /// Makes the textures, once. Materials asked for before this is done are plain.
  func makeTextures() async {
    guard textures.isEmpty else { return }
    for texture in GenzTexture.allCases {
      guard
        let images = texture.images(),
        let colour = try? await TextureResource(
          image: images.colour, options: .init(semantic: .color))
      else { continue }
      var normal: TextureResource?
      if let image = images.normal {
        normal = try? await TextureResource(image: image, options: .init(semantic: .normal))
      }
      textures[texture] = (colour, normal)
    }
  }
}

/// The small repeating textures of the styled rooms, drawn in code.
enum GenzTexture: CaseIterable, Hashable {
  /// Long grain with darker rings, running along u.
  case wood
  /// Chunky knitted V stitches in columns.
  case knit
  /// A fine linen weave.
  case linen

  private static let size = 128

  /// The colour, near white so the material's colour shows through, and a normal map where the
  /// texture has relief.
  func images() -> (colour: CGImage, normal: CGImage?)? {
    let size = Self.size
    var heights = [Float](repeating: 0, count: size * size)
    for y in 0..<size {
      for x in 0..<size {
        heights[y * size + x] = height(Float(x) / Float(size), Float(y) / Float(size))
      }
    }
    let colour = Self.image(size) { x, y in
      let height = heights[y * size + x]
      let value = shade(height)
      return (value, value, value)
    }
    let normal = Self.image(size) { x, y in
      let left = heights[y * size + (x + size - 1) % size]
      let right = heights[y * size + (x + 1) % size]
      let up = heights[((y + size - 1) % size) * size + x]
      let down = heights[((y + 1) % size) * size + x]
      let strength = relief
      var normal = SIMD3<Float>((left - right) * strength, (up - down) * strength, 1)
      normal = simd_normalize(normal)
      let encoded = normal * 0.5 + 0.5
      return (encoded.x, encoded.y, encoded.z)
    }
    guard let colour else { return nil }
    return (colour, normal)
  }

  private var relief: Float {
    switch self {
    case .wood: 0.35
    case .knit: 7
    case .linen: 1.2
    }
  }

  /// Height from 0 to 1 at (u, v), tiling at the edges.
  private func height(_ u: Float, _ v: Float) -> Float {
    let tau = 2 * Float.pi
    switch self {
    case .wood:
      let wobble = 0.5 * sin(u * tau + 1.3) + 0.2 * sin(u * tau * 3 + v * tau)
      let rings = sin((v * 6 + wobble * 0.12) * tau)
      let fine = sin((v * 23 + wobble * 0.3) * tau)
      return 0.5 + 0.3 * rings + 0.2 * fine
    case .knit:
      let columns: Float = 8
      let rows: Float = 10
      let across = (u * columns).truncatingRemainder(dividingBy: 1) * 2 - 1
      let down = (v * rows + abs(across) * 0.5).truncatingRemainder(dividingBy: 1)
      let stitch = sin(down * .pi) * (1 - pow(abs(across), 4))
      return max(stitch, 0)
    case .linen:
      let warp = sin(u * tau * 32) * 0.5 + 0.5
      let weft = sin(v * tau * 32) * 0.5 + 0.5
      let slub = 0.5 + 0.5 * sin(v * tau * 3 + sin(u * tau * 2) * 2)
      return (warp * 0.5 + weft * 0.5) * 0.8 + slub * 0.2
    }
  }

  /// How light the colour is at `height`.
  private func shade(_ height: Float) -> Float {
    switch self {
    case .wood: 0.84 + 0.16 * height
    case .knit: 0.7 + 0.3 * height
    case .linen: 0.93 + 0.07 * height
    }
  }

  private static func image(_ size: Int, _ pixel: (Int, Int) -> (Float, Float, Float)) -> CGImage? {
    var bytes = [UInt8](repeating: 255, count: size * size * 4)
    for y in 0..<size {
      for x in 0..<size {
        let (red, green, blue) = pixel(x, y)
        let index = (y * size + x) * 4
        bytes[index] = UInt8(max(min(red, 1), 0) * 255)
        bytes[index + 1] = UInt8(max(min(green, 1), 0) * 255)
        bytes[index + 2] = UInt8(max(min(blue, 1), 0) * 255)
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}
