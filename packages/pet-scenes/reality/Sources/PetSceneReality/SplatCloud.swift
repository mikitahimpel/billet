import Foundation
import simd

/// Why a splat file would not open.
enum SplatLoadError: Error, Equatable {
  case missing(String)
  case unreadable(String)
}

/// A Gaussian-splat body, decoded from a `.bsplat` file: every splat's rest shape in the cat mesh's
/// own space (the skinned model's bind pose) and up to four joints that move it.
///
/// The file is DEFLATE-compressed and quantised (about 25 bytes a splat before compression); see
/// `scripts/pack_splat.py` beside the cat sources. `rest` is the layout `GaussianSplatResource`
/// reads: 14 floats a splat, position, log scale, rotation (w x y z), logit opacity, and the
/// zeroth spherical-harmonic colour.
struct SplatCloud: Sendable {
  static let floatsPerSplat = 14
  static let shC0: Float = 0.282_094_79

  let count: Int
  /// USD joint paths, such as `root/spine_01/spine_02`.
  let jointNames: [String]
  let rest: [Float]
  let joints: [SIMD4<UInt8>]
  /// Each splat's joint weights, summing to 1.
  let weights: [SIMD4<Float>]

  static func load(named name: String, in bundle: Bundle) throws(SplatLoadError) -> SplatCloud {
    guard
      let url = bundle.url(
        forResource: name, withExtension: "bsplat", subdirectory: CatCatalog.folder)
    else { throw .missing(name) }
    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
      throw .unreadable(name)
    }
    return try decode(data, name: name)
  }

  static func decode(_ compressed: Data, name: String) throws(SplatLoadError) -> SplatCloud {
    guard let data = try? (compressed as NSData).decompressed(using: .zlib) as Data else {
      throw .unreadable(name)
    }
    var reader = Reader(data: data)
    guard reader.bytes(4) == Data("BSPL".utf8), reader.u32() == 1,
      let count = reader.u32().map(Int.init), let jointCount = reader.u32().map(Int.init),
      let box = reader.floats(8)
    else { throw .unreadable(name) }
    var jointNames: [String] = []
    for _ in 0..<jointCount {
      guard let length = reader.u16(), let bytes = reader.bytes(Int(length)) else {
        throw .unreadable(name)
      }
      jointNames.append(String(decoding: bytes, as: UTF8.self))
    }
    reader.align(4)
    guard let positions = reader.bytes(count * 6), let scales = reader.bytes(count * 3),
      let rotations = reader.bytes(count * 4), let opacities = reader.bytes(count),
      let colours = reader.bytes(count * 3), let jointBytes = reader.bytes(count * 4),
      let weightBytes = reader.bytes(count * 4), reader.isAtEnd
    else { throw .unreadable(name) }

    let low = SIMD3(box[0], box[1], box[2])
    let span = SIMD3(box[3], box[4], box[5]) - low
    let scaleLow = box[6]
    let scaleSpan = box[7] - box[6]
    var rest = [Float](repeating: 0, count: count * floatsPerSplat)
    var joints = [SIMD4<UInt8>](repeating: .zero, count: count)
    var weights = [SIMD4<Float>](repeating: .zero, count: count)
    positions.withUnsafeBytes { p in
      scales.withUnsafeBytes { s in
        rotations.withUnsafeBytes { r in
          for i in 0..<count {
            let o = i * floatsPerSplat
            for axis in 0..<3 {
              let q = Float(p.loadUnaligned(fromByteOffset: (i * 3 + axis) * 2, as: UInt16.self))
              rest[o + axis] = low[axis] + q / 65535 * span[axis]
              let scale = s.load(fromByteOffset: i * 3 + axis, as: UInt8.self)
              rest[o + 3 + axis] = scaleLow + Float(scale) / 255 * scaleSpan
            }
            func component(_ c: Int) -> Float {
              Float(r.load(fromByteOffset: i * 4 + c, as: Int8.self))
            }
            var q = SIMD4<Float>(component(0), component(1), component(2), component(3))
            let length = simd_length(q)
            q = length > 0 ? q / length : SIMD4(1, 0, 0, 0)
            for c in 0..<4 { rest[o + 6 + c] = q[c] }
          }
        }
      }
    }
    for i in 0..<count {
      let o = i * floatsPerSplat
      let alpha = min(max(Float(opacities[opacities.startIndex + i]) / 255, 0.001), 0.999)
      rest[o + 10] = log(alpha / (1 - alpha))
      for c in 0..<3 {
        let colour = Float(colours[colours.startIndex + i * 3 + c]) / 255
        rest[o + 11 + c] = (colour - 0.5) / shC0
      }
      let j = jointBytes.startIndex + i * 4
      joints[i] = SIMD4(jointBytes[j], jointBytes[j + 1], jointBytes[j + 2], jointBytes[j + 3])
      let w = weightBytes.startIndex + i * 4
      let raw = SIMD4<Float>(
        Float(weightBytes[w]), Float(weightBytes[w + 1]), Float(weightBytes[w + 2]),
        Float(weightBytes[w + 3]))
      let sum = raw.sum()
      weights[i] = sum > 0 ? raw / sum : SIMD4(1, 0, 0, 0)
    }
    return SplatCloud(
      count: count, jointNames: jointNames, rest: rest, joints: joints, weights: weights)
  }

  /// For each of the file's joints, its index among `skeleton`'s joint names, matched by the last
  /// path component; nil when one is missing.
  func jointMap(to skeleton: [String]) -> [Int]? {
    let leaves = skeleton.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
    var map: [Int] = []
    for name in jointNames {
      let leaf = name.split(separator: "/").last.map(String.init) ?? name
      guard let index = leaves.firstIndex(of: leaf) else { return nil }
      map.append(index)
    }
    return map
  }

  private struct Reader {
    let data: Data
    var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func bytes(_ n: Int) -> Data? {
      guard n >= 0, offset + n <= data.count else { return nil }
      defer { offset += n }
      let start = data.startIndex + offset
      return data[start..<(start + n)]
    }

    mutating func u16() -> UInt16? {
      bytes(2).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) } }
    }

    mutating func u32() -> UInt32? {
      bytes(4).map { $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
    }

    mutating func floats(_ n: Int) -> [Float]? {
      bytes(n * 4).map { chunk in
        chunk.withUnsafeBytes { raw in
          (0..<n).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
      }
    }

    mutating func align(_ n: Int) {
      offset = (offset + n - 1) / n * n
    }
  }
}
