import CoreGraphics
import Foundation
import Metal
import simd

/// An orthographic camera: world space to camera space (looking down -Z), and its zoom.
struct Camera {
  var toCamera: simd_float4x4
  var pixelsPerUnit: Float

  /// Looks at `target` from the side `from` points to.
  init(target: SIMD3<Float>, from direction: SIMD3<Float>, pixelsPerUnit: Float) {
    let back = simd_normalize(direction)
    let right = simd_normalize(simd_cross([0, 1, 0], back))
    let up = simd_cross(back, right)
    toCamera = simd_float4x4(rows: [
      SIMD4(right, -simd_dot(right, target)),
      SIMD4(up, -simd_dot(up, target)),
      SIMD4(back, -simd_dot(back, target)),
      [0, 0, 0, 1],
    ])
    self.pixelsPerUnit = pixelsPerUnit
  }

  /// A world point in a `size` picture, origin bottom left.
  func project(_ p: SIMD3<Float>, in size: CGSize) -> CGPoint {
    let c = toCamera * SIMD4(p, 1)
    return CGPoint(
      x: size.width / 2 + CGFloat(c.x * pixelsPerUnit),
      y: size.height / 2 + CGFloat(c.y * pixelsPerUnit))
  }
}

/// Draws skinned splat bodies offscreen and hands the picture back, premultiplied on clear.
final class SplatRenderer {
  private struct View {
    var toCamera: simd_float4x4
    var viewport: SIMD2<Float>
    var pixelsPerUnit: Float
    var pad: Float = 0
  }

  enum Failure: Error { case noGPU }

  let width: Int
  let height: Int
  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private let pipeline: any MTLRenderPipelineState
  private let target: any MTLTexture
  private var order: any MTLBuffer
  private var depths: [Float]
  private var starts = [Int](repeating: 0, count: 65537)

  init(width: Int, height: Int, splats: Int) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
      let library = device.makeDefaultLibrary(),
      let order = device.makeBuffer(length: splats * 4)
    else { throw Failure.noGPU }
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "splatVertex")
    descriptor.fragmentFunction = library.makeFunction(name: "splatFragment")
    let color = descriptor.colorAttachments[0]!
    color.pixelFormat = .bgra8Unorm
    color.isBlendingEnabled = true
    color.sourceRGBBlendFactor = .one
    color.sourceAlphaBlendFactor = .one
    color.destinationRGBBlendFactor = .oneMinusSourceAlpha
    color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    let texture = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    texture.usage = [.renderTarget]
    texture.storageMode = .shared
    guard let target = device.makeTexture(descriptor: texture) else { throw Failure.noGPU }
    self.device = device
    self.queue = queue
    self.target = target
    self.order = order
    depths = [Float](repeating: 0, count: splats)
    self.width = width
    self.height = height
  }

  /// `bodies` with each one's model-to-world transform, drawn in the order given.
  func draw(_ bodies: [(body: DrawnBody, toWorld: simd_float4x4)], camera: Camera) -> CGImage? {
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    for (index, item) in bodies.enumerated() {
      item.body.settle()
      let toCamera = camera.toCamera * item.toWorld
      let count = item.body.count
      let moving = item.body.moving.contents().bindMemory(to: Float.self, capacity: count * 8)
      let row = SIMD4(toCamera.columns.0.z, toCamera.columns.1.z, toCamera.columns.2.z, toCamera.columns.3.z)
      // A counting sort on depth, far to near.
      var low = Float.infinity, high = -Float.infinity
      depths.withUnsafeMutableBufferPointer { depths in
        for i in 0..<count {
          let depth = row.x * moving[8 * i] + row.y * moving[8 * i + 1] + row.z * moving[8 * i + 2] + row.w
          depths[i] = depth
          low = min(low, depth)
          high = max(high, depth)
        }
      }
      if order.length < count * 4, let bigger = device.makeBuffer(length: count * 4) { order = bigger }
      let ids = order.contents().bindMemory(to: UInt32.self, capacity: count)
      let buckets = starts.count - 1
      let step = Float(buckets - 1) / max(high - low, 1e-9)
      starts.withUnsafeMutableBufferPointer { starts in
        depths.withUnsafeBufferPointer { depths in
          for b in 0...buckets { starts[b] = 0 }
          for i in 0..<count { starts[Int((depths[i] - low) * step) + 1] += 1 }
          for b in 1...buckets { starts[b] += starts[b - 1] }
          for i in 0..<count {
            let b = Int((depths[i] - low) * step)
            ids[starts[b]] = UInt32(i)
            starts[b] += 1
          }
        }
      }

      var view = View(
        toCamera: toCamera, viewport: [Float(width), Float(height)], pixelsPerUnit: camera.pixelsPerUnit)
      guard let commands = queue.makeCommandBuffer(),
        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
      else { return nil }
      encoder.setRenderPipelineState(pipeline)
      encoder.setVertexBuffer(item.body.moving, offset: 0, index: 0)
      encoder.setVertexBuffer(item.body.still, offset: 0, index: 1)
      encoder.setVertexBuffer(order, offset: 0, index: 2)
      encoder.setVertexBytes(&view, length: MemoryLayout<View>.stride, index: 3)
      encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
      encoder.endEncoding()
      commands.commit()
      commands.waitUntilCompleted()
      if index == 0 { pass.colorAttachments[0].loadAction = .load }
    }
    if bodies.isEmpty {
      guard let commands = queue.makeCommandBuffer(),
        let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
      else { return nil }
      encoder.endEncoding()
      commands.commit()
      commands.waitUntilCompleted()
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(
      &bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    lastAlpha = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(
        rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  /// Coverage of the picture drawn last, row by row from the top.
  private(set) var lastAlpha: [UInt8] = []
}
