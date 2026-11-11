import RealityKit
import UIKit

/// Static clay geometry merged per material: a whole set of cabinets, tiles and fruit becomes a handful of meshes, so
/// RealityKit draws a handful of things where a model per box would draw hundreds. Nothing here moves after `commit`.
struct MeshBatch {
    private struct Key: Hashable {
        let hex: UInt32
        let roughness: Float
    }

    private struct Bucket {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func add(_ corners: [SIMD3<Float>], _ normal: SIMD3<Float>) {
            let base = UInt32(positions.count)
            positions += corners
            normals += Array(repeating: normal, count: corners.count)
            indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
    }

    private var buckets: [Key: Bucket] = [:]

    mutating func box(_ size: SIMD3<Float>, at center: SIMD3<Float>, rotation: simd_quatf = .identity,
                      _ hex: UInt32, roughness: Float = 0.82) {
        let h = size / 2
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [-1, 0, 0], [0, 1, 0]),
            ([1, 0, 0], [0, 0, -1], [0, 1, 0]), ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
            ([0, 1, 0], [1, 0, 0], [0, 0, -1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
        ]
        var bucket = buckets[Key(hex: hex, roughness: roughness)] ?? Bucket()
        for face in faces {
            let n = face.normal * h
            let u = face.u * h, v = face.v * h
            let corners = [n - u - v, n + u - v, n + u + v, n - u + v].map { center + rotation.act($0) }
            bucket.add(corners, rotation.act(face.normal))
        }
        buckets[Key(hex: hex, roughness: roughness)] = bucket
    }

    /// A cylinder standing along local y, turned by `rotation` about its center.
    mutating func cylinder(height: Float, radius: Float, at center: SIMD3<Float>, rotation: simd_quatf = .identity,
                           _ hex: UInt32, roughness: Float = 0.82, sides: Int = 14) {
        var bucket = buckets[Key(hex: hex, roughness: roughness)] ?? Bucket()
        let half = height / 2
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi, a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let p0 = SIMD3<Float>(cos(a0), 0, sin(a0)), p1 = SIMD3<Float>(cos(a1), 0, sin(a1))
            func place(_ p: SIMD3<Float>, _ y: Float) -> SIMD3<Float> { center + rotation.act(p * radius + [0, y, 0]) }
            let base = UInt32(bucket.positions.count)
            bucket.positions += [place(p0, -half), place(p1, -half), place(p1, half), place(p0, half)]
            bucket.normals += [rotation.act(p0), rotation.act(p1), rotation.act(p1), rotation.act(p0)]
            bucket.indices += [base, base + 2, base + 1, base, base + 3, base + 2]
            for (y, up) in [(half, Float(1)), (-half, Float(-1))] {
                let cap = UInt32(bucket.positions.count)
                bucket.positions += [place(.zero, y), place(p0, y), place(p1, y)]
                bucket.normals += Array(repeating: rotation.act([0, up, 0]), count: 3)
                bucket.indices += up > 0 ? [cap, cap + 2, cap + 1] : [cap, cap + 1, cap + 2]
            }
        }
        buckets[Key(hex: hex, roughness: roughness)] = bucket
    }

    mutating func sphere(radius: Float, at center: SIMD3<Float>, scale: SIMD3<Float> = .one, _ hex: UInt32,
                         roughness: Float = 0.82) {
        var bucket = buckets[Key(hex: hex, roughness: roughness)] ?? Bucket()
        let rings = 7, sides = 12
        func point(_ r: Int, _ s: Int) -> (SIMD3<Float>, SIMD3<Float>) {
            let phi = Float(r) / Float(rings) * .pi, theta = Float(s) / Float(sides) * 2 * .pi
            let n = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            return (center + n * radius * scale, simd_normalize(n / scale))
        }
        for r in 0..<rings {
            for s in 0..<sides {
                let q = [point(r, s), point(r + 1, s), point(r + 1, s + 1), point(r, s + 1)]
                let base = UInt32(bucket.positions.count)
                bucket.positions += q.map { $0.0 }
                bucket.normals += q.map { $0.1 }
                bucket.indices += [base, base + 2, base + 1, base, base + 3, base + 2]
            }
        }
        buckets[Key(hex: hex, roughness: roughness)] = bucket
    }

    /// One model per material, under `parent`.
    func commit(into parent: Entity) {
        for (key, bucket) in buckets where !bucket.indices.isEmpty {
            var descriptor = MeshDescriptor(name: "batch")
            descriptor.positions = MeshBuffers.Positions(bucket.positions)
            descriptor.normals = MeshBuffers.Normals(bucket.normals)
            descriptor.primitives = .triangles(bucket.indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            parent.addChild(ModelEntity(mesh: mesh, materials: [Clay.matte(key.hex, roughness: key.roughness)]))
        }
    }
}

extension Entity {
    /// Whether the top of an image is v = 1 or v = 0 on RealityKit's own planes, read from one so a mesh with its own
    /// coordinates matches.
    private static let planeTopV: Float = {
        let mesh = MeshResource.generatePlane(width: 1, height: 1)
        guard let part = mesh.contents.models.first?.parts.first, let coordinates = part.textureCoordinates else { return 1 }
        let positions = Array(part.positions.elements)
        let uvs = Array(coordinates.elements)
        guard positions.count == uvs.count,
              let top = positions.indices.max(by: { positions[$0].y < positions[$1].y }) else { return 1 }
        return uvs[top].y > 0.5 ? 1 : 0
    }()

    /// A tall wall standing on the floor from `start` to `end` (x, z), facing the side its left-to-right direction
    /// crosses up to, painted with a vertical `top`-to-`bottom` fade so the room has a ceiling shade and no edge.
    @discardableResult
    func fadedWall(from start: SIMD2<Float>, to end: SIMD2<Float>, height: Float, top: UInt32, bottom: UInt32) -> Entity? {
        guard let texture = Self.fadeTexture(top: top, bottom: bottom) else { return nil }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(texture))
        material.roughness = .init(floatLiteral: 0.9)
        material.metallic = .init(floatLiteral: 0)
        material.faceCulling = .none
        let a = SIMD3<Float>(start.x, 0, start.y), b = SIMD3<Float>(end.x, 0, end.y)
        let normal = simd_normalize(simd_cross(b - a, [0, 1, 0]))
        let topIsOne = Self.planeTopV > 0.5
        let corners = [a, b, b + [0, height, 0], a + [0, height, 0]]
        let uvs: [SIMD2<Float>] = [[0, topIsOne ? 0 : 1], [1, topIsOne ? 0 : 1], [1, topIsOne ? 1 : 0], [0, topIsOne ? 1 : 0]]
        var piece = MeshDescriptor(name: "wall")
        piece.positions = MeshBuffers.Positions(corners)
        piece.normals = MeshBuffers.Normals(Array(repeating: normal, count: 4))
        piece.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        piece.primitives = .triangles([0, 1, 2, 0, 2, 3])
        guard let mesh = try? MeshResource.generate(from: [piece]) else { return nil }
        let wall = ModelEntity(mesh: mesh, materials: [material])
        addChild(wall)
        return wall
    }

    private static func fadeTexture(top: UInt32, bottom: UInt32) -> TextureResource? {
        let size = CGSize(width: 4, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colors = [UIColor(hex: top).cgColor, UIColor(hex: bottom).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else {
                return
            }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
        return image.cgImage.flatMap { try? TextureResource(image: $0, options: .init(semantic: .color)) }
    }
}
