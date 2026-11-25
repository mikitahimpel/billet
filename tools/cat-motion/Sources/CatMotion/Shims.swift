import Foundation
import Metal
import RealityKit
import simd

// What the cat's files take from the rest of the app, for a Mac without RealityKit's splats: the same
// names, with the skinned splats landing in a buffer the harness draws itself.

extension simd_quatf {
  static func x(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
  static func y(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
  static func z(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }
}

nonisolated func smoothstep(_ x: Float, _ low: Float, _ high: Float) -> Float {
  let u = min(max((x - low) / (high - low), 0), 1)
  return u * u * (3 - 2 * u)
}

struct Splat {
  let entity: Entity
  let count: Int
  let replace: (any MTLCommandBuffer) -> any MTLBuffer
  let rest: [Float]
}

/// A body as the harness draws it: the buffer its skinner writes, and the part that never moves.
final class DrawnBody {
  let name: String
  let count: Int
  let entity: Entity
  let moving: any MTLBuffer
  let still: any MTLBuffer
  /// The skinning pass that last wrote `moving`; read the buffer only once it has completed.
  var pending: (any MTLCommandBuffer)?

  init(name: String, count: Int, entity: Entity, moving: any MTLBuffer, still: any MTLBuffer) {
    self.name = name
    self.count = count
    self.entity = entity
    self.moving = moving
    self.still = still
  }

  func settle() {
    pending?.waitUntilCompleted()
    pending = nil
  }
}

nonisolated enum SplatLoader {
  nonisolated enum Failure: Error {
    case missing(String)
    case unsupportedFormat(String)
  }

  nonisolated struct File {
    let name: String
    let count: Int
    let moving: [Float]
    let still: [Float]
  }

  @MainActor static var drawn: [String: DrawnBody] = [:]

  private static let fields =
    "x y z scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3 opacity f_dc_0 f_dc_1 f_dc_2"

  static func read(named name: String, in bundle: Bundle = .main) throws -> File {
    guard let url = bundle.url(forResource: name, withExtension: "ply") else {
      throw Failure.missing(name)
    }
    let data = try Data(contentsOf: url)
    guard let end = data.range(of: Data("end_header\n".utf8)) else {
      throw Failure.unsupportedFormat(name)
    }
    let header = String(decoding: data[..<end.lowerBound], as: UTF8.self).split(separator: "\n")
    let properties = header.filter { $0.hasPrefix("property float ") }.map { $0.dropFirst(15) }
    let stride = properties.count * MemoryLayout<Float>.size
    let body = data[end.upperBound...]
    guard properties.joined(separator: " ") == fields,
      let countLine = header.first(where: { $0.hasPrefix("element vertex ") }),
      let count = Int(countLine.dropFirst(15)),
      body.count == count * stride
    else { throw Failure.unsupportedFormat(name) }
    var moving = [Float](repeating: 0, count: 8 * count)
    var still = moving
    body.withUnsafeBytes { raw in
      for i in 0..<count {
        func value(_ k: Int) -> Float {
          raw.loadUnaligned(fromByteOffset: i * stride + 4 * k, as: Float.self)
        }
        for k in 0..<3 { moving[8 * i + k] = value(k) }
        for k in 0..<4 { moving[8 * i + 4 + k] = value(6 + k) }
        for k in 0..<3 { still[8 * i + k] = value(3 + k) }
        for k in 0..<4 { still[8 * i + 3 + k] = value(10 + k) }
      }
    }
    return File(name: name, count: count, moving: moving, still: still)
  }

  @MainActor static func make(_ file: File) throws -> Splat {
    guard let device = MTLCreateSystemDefaultDevice(),
      let moving = device.makeBuffer(bytes: file.moving, length: file.moving.count * 4),
      let still = device.makeBuffer(bytes: file.still, length: file.still.count * 4)
    else { throw Failure.unsupportedFormat(file.name) }
    let body = DrawnBody(
      name: file.name, count: file.count, entity: Entity(), moving: moving, still: still)
    drawn[file.name] = body
    return Splat(
      entity: body.entity, count: file.count,
      replace: { commands in
        body.pending = commands
        return moving
      }, rest: file.moving)
  }
}

extension Entity {
  func forEachDescendant(_ body: (Entity) -> Void) {
    for child in children {
      body(child)
      child.forEachDescendant(body)
    }
  }
}
