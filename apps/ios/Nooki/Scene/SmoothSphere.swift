import RealityKit
import simd

/// A unit sphere with as many facets as its size on screen can show. `MeshResource.generateSphere` makes 8,064
/// triangles for a bulb a few pixels wide as for a ball a hundred pixels wide.
enum SmoothSphere {
    /// Segments round the equator for a sphere of `radius` metres seen at `pixelsPerMetre`, keeping the silhouette
    /// within `tolerance` pixels of the true circle. Even, at least 12, at most 64 (RealityKit's own).
    static func segments(radius: Float, pixelsPerMetre: Float = 800, tolerance: Float = 0.5) -> Int {
        let pixels = max(radius * pixelsPerMetre, tolerance)
        let step = 2 * acos(max(0, 1 - tolerance / pixels))
        let around = Int((2 * Float.pi / max(step, 0.0001)).rounded(.up))
        return min(64, max(12, around + around % 2))
    }

    @MainActor
    static func mesh(segments: Int) -> MeshResource? {
        let rings = segments / 2
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for i in 0...rings {
            let polar = Float.pi * Float(i) / Float(rings)
            for j in 0...segments {
                let azimuth = 2 * Float.pi * Float(j) / Float(segments)
                let p = SIMD3(sin(polar) * cos(azimuth), cos(polar), sin(polar) * sin(azimuth))
                positions.append(p)
                normals.append(p)
            }
        }
        let width = UInt32(segments + 1)
        for i in 0..<rings {
            for j in 0..<segments {
                let a = UInt32(i) * width + UInt32(j), b = a + 1, c = a + width, d = c + 1
                // Outward-facing front sides; the poles collapse one triangle of each quad.
                if i != 0 { indices += [a, b, c] }
                if i != rings - 1 { indices += [b, d, c] }
            }
        }
        let a = positions[Int(indices[0])], b = positions[Int(indices[1])], c = positions[Int(indices[2])]
        if simd_dot(simd_cross(b - a, c - a), a + b + c) < 0 {
            for t in stride(from: 0, to: indices.count, by: 3) { indices.swapAt(t + 1, t + 2) }
        }
        var descriptor = MeshDescriptor(name: "smoothSphere")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
