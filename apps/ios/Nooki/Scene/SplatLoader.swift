import CoreGraphics
import Foundation
import Metal
import RealityKit

/// A loaded splat: the entity drawing it, the buffer it draws from and the file's own splats.
struct Splat {
    let entity: Entity
    let count: Int
    /// Hands out the buffer in GaussianSplatResource's interleaved layout, 14 floats per splat, for the given
    /// command buffer to rewrite; rewriting it moves the splats. A closure, since LowLevelBuffer needs iOS 26.
    let replace: (any MTLCommandBuffer) -> any MTLBuffer
    /// The file's splats in the same layout.
    let rest: Data
}

/// Loads Gaussian splats written by nooki-scene/generate/make_splat.py.
/// The PLY body already holds GaussianSplatResource's interleaved layout (14 floats per splat), so it is copied as is.
nonisolated enum SplatLoader {
    nonisolated enum Failure: Error {
        case missing(String)
        case unsupportedFormat(String)
    }

    /// A PLY read and checked: `count` splats of `stride` bytes in `body`.
    nonisolated struct File {
        let name: String
        let count: Int
        let stride: Int
        let body: Data
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
        return File(name: name, count: count, stride: stride, body: body)
    }

    @MainActor static func make(_ file: File) throws -> Splat {
        #if targetEnvironment(simulator)
        throw Failure.unsupportedFormat(file.name)
        #else
        guard #available(iOS 27, *) else { throw Failure.unsupportedFormat(file.name) }
        let body = file.body, stride = file.stride, count = file.count
        let floatSize = MemoryLayout<Float>.size
        // Capacities padded only to 16 bytes pass validation but render scrambled.
        let buffer = try LowLevelBuffer(descriptor: .init(capacity: (body.count + 255) & ~0xFF, sizeMultiple: 16))
        buffer.withUnsafeMutableBytes { $0.copyBytes(from: body) }
        func field(_ format: MTLAttributeFormat, at index: Int) -> GaussianSplatResource.BufferDescriptor {
            .init(buffer: buffer, format: format, stride: stride, offset: index * floatSize)
        }

        let splats = try GaussianSplatResource.BufferResource(
            count: count,
            position: field(.float3, at: 0),
            scale: field(.float3, at: 3),
            rotation: field(.float4, at: 6),
            opacity: field(.float, at: 10),
            sphericalHarmonics: (field(.float3, at: 11), .zero)
        )
        let resource = GaussianSplatResource(splats)
        // The file keeps the trained values: log scales and logit opacities.
        resource.scaleActivation = .exponential
        resource.opacityActivation = .sigmoid
        // The SH colors are sRGB; in another space the splats come out colorless.
        if let srgb = CGColorSpace(name: CGColorSpace.sRGB) { resource.colorSpace = srgb }

        let entity = Entity()
        entity.components.set(GaussianSplatComponent(resource))
        return Splat(entity: entity, count: count, replace: { buffer.replace(using: $0) }, rest: body)
        #endif
    }
}
