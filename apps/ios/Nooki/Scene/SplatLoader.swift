import CoreGraphics
import Foundation
import Metal
import RealityKit

/// A loaded splat: the entity drawing it, the buffer it draws from and the file's own splats.
struct Splat {
    let entity: Entity
    let count: Int
    /// Hands out the buffer of the splats' moving part, laid out as `SplatLoader.File.moving`, for the given command
    /// buffer to rewrite; rewriting it moves the splats. A closure, since LowLevelBuffer needs iOS 26.
    let replace: (any MTLCommandBuffer) -> any MTLBuffer
    /// The file's moving part at rest.
    let rest: [Float]
}

/// Loads Gaussian splats written by nooki-scene/generate/make_splat.py.
/// The PLY body (14 floats per splat) is split in two buffers: the part skinning rewrites each frame and the part it
/// never touches, so a frame moves 32 bytes a splat instead of 56.
nonisolated enum SplatLoader {
    nonisolated enum Failure: Error {
        case missing(String)
        case unsupportedFormat(String)
    }

    /// A PLY read and checked, `count` splats of 8 floats in each part.
    nonisolated struct File {
        let name: String
        let count: Int
        /// Center, a pad, rotation (w first).
        let moving: [Float]
        /// Log scale, logit opacity, SH color, a pad.
        let still: [Float]
    }

    private static let fields = "x y z scale_0 scale_1 scale_2 rot_0 rot_1 rot_2 rot_3 opacity f_dc_0 f_dc_1 f_dc_2"

    /// RealityKit renders splats only from iOS 27 on Apple7-family GPUs, and the simulator SDK has no splat API at all.
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        guard #available(iOS 27, *) else { return false }
        return MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
        #endif
    }

    /// Reads the whole file into memory, so the copy in `make` never waits on the disk.
    static func read(named name: String, in bundle: Bundle = .main) throws -> File {
        guard let url = bundle.url(forResource: name, withExtension: "ply") else { throw Failure.missing(name) }
        let data = try Data(contentsOf: url)
        guard let end = data.range(of: Data("end_header\n".utf8)) else { throw Failure.unsupportedFormat(name) }

        let header = String(decoding: data[..<end.lowerBound], as: UTF8.self).split(separator: "\n")
        let properties = header.filter { $0.hasPrefix("property float ") }.map { $0.dropFirst(15) }
        let stride = properties.count * MemoryLayout<Float>.size
        let body = data[end.upperBound...]
        guard header.contains("format binary_little_endian 1.0"),
              properties.joined(separator: " ") == fields,
              let countLine = header.first(where: { $0.hasPrefix("element vertex ") }),
              let count = Int(countLine.dropFirst(15)),
              body.count == count * stride
        else { throw Failure.unsupportedFormat(name) }
        var moving = [Float](repeating: 0, count: 8 * count), still = moving
        body.withUnsafeBytes { raw in
            moving.withUnsafeMutableBufferPointer { m in
                still.withUnsafeMutableBufferPointer { s in
                    for i in 0..<count {
                        func value(_ k: Int) -> Float { raw.loadUnaligned(fromByteOffset: i * stride + 4 * k, as: Float.self) }
                        for k in 0..<3 { m[8 * i + k] = value(k) }
                        for k in 0..<4 { m[8 * i + 4 + k] = value(6 + k) }
                        for k in 0..<3 { s[8 * i + k] = value(3 + k) }
                        for k in 0..<4 { s[8 * i + 3 + k] = value(10 + k) }
                    }
                }
            }
        }
        return File(name: name, count: count, moving: moving, still: still)
    }

    @MainActor static func make(_ file: File) throws -> Splat {
        #if targetEnvironment(simulator)
        throw Failure.unsupportedFormat(file.name)
        #else
        guard #available(iOS 27, *) else { throw Failure.unsupportedFormat(file.name) }
        let count = file.count, floatSize = MemoryLayout<Float>.size
        func buffer(_ values: [Float]) throws -> LowLevelBuffer {
            // Capacities padded only to 16 bytes pass validation but render scrambled.
            let bytes = values.count * floatSize
            let buffer = try LowLevelBuffer(descriptor: .init(capacity: (bytes + 255) & ~0xFF, sizeMultiple: 16))
            buffer.withUnsafeMutableBytes { out in values.withUnsafeBytes { out.copyMemory(from: $0) } }
            return buffer
        }
        let moving = try buffer(file.moving), still = try buffer(file.still)
        func field(_ buffer: LowLevelBuffer, _ format: MTLAttributeFormat, at index: Int) -> GaussianSplatResource.BufferDescriptor {
            .init(buffer: buffer, format: format, stride: 8 * floatSize, offset: index * floatSize)
        }

        let splats = try GaussianSplatResource.BufferResource(
            count: count,
            position: field(moving, .float3, at: 0),
            scale: field(still, .float3, at: 0),
            rotation: field(moving, .float4, at: 4),
            opacity: field(still, .float, at: 3),
            sphericalHarmonics: (field(still, .float3, at: 4), .zero)
        )
        let resource = GaussianSplatResource(splats)
        // The file keeps the trained values: log scales and logit opacities.
        resource.scaleActivation = .exponential
        resource.opacityActivation = .sigmoid
        // The SH colors are sRGB; in another space the splats come out colorless.
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { resource.colorSpace = srgb }

        let entity = Entity()
        entity.components.set(GaussianSplatComponent(resource))
        return Splat(entity: entity, count: count, replace: { moving.replace(using: $0) }, rest: file.moving)
        #endif
    }
}
