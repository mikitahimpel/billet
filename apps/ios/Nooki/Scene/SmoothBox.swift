import RealityKit
import simd

/// A rounded box with as many facets on each corner as its radius can show: 2 per quarter turn of a corner for a
/// fillet a few pixels wide, more for a wide one, none for a square corner. `MeshResource.generateBox(cornerRadius:)`
/// tessellates every corner the same, however small.
enum SmoothBox {
    /// Facets along a quarter turn of a corner that keep the silhouette within `tolerance` of the true arc, for a
    /// fillet of `radius` metres seen at `pixelsPerMetre`.
    static func facets(radius: Float, pixelsPerMetre: Float = 800, tolerance: Float = 0.5) -> Int {
        let pixels = radius * pixelsPerMetre
        guard pixels > tolerance else { return radius > 0.0001 ? 2 : 0 }
        let step = 2 * acos(max(0, 1 - tolerance / pixels))
        return max(2, 2 * Int((Float.pi / 2 / step / 2).rounded(.up)))
    }

    /// `radius` must leave a flat of at least 0.001 on every side.
    @MainActor
    static func mesh(width: Float, height: Float, depth: Float, radius: Float) -> MeshResource? {
        let half = SIMD3<Float>(width, height, depth) / 2
        let r = max(0, min(radius, min(half.x, min(half.y, half.z)) - 0.0005))
        let quarter = facets(radius: r)
        // Facets per 45 degrees on each side of a face's middle; a square box is one quad a face.
        let k = quarter / 2
        var stations: [(tilt: Float, side: Float)] = []
        for j in 0...k { stations.append((k == 0 ? 0 : -Float.pi / 4 * Float(k - j) / Float(k), -1)) }
        for j in 0...k { stations.append((k == 0 ? 0 : Float.pi / 4 * Float(j) / Float(k), 1)) }
        let inner = half - SIMD3(repeating: r)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []
        let n = stations.count
        for axis in 0..<3 {
            let b = (axis + 1) % 3, c = (axis + 2) % 3
            for sign: Float in [-1, 1] {
                let first = UInt32(positions.count)
                for sb in stations {
                    for sc in stations {
                        var direction = SIMD3<Float>.zero
                        direction[axis] = sign
                        direction[b] = tan(sb.tilt)
                        direction[c] = tan(sc.tilt)
                        let normal = simd_normalize(direction)
                        var centre = SIMD3<Float>.zero
                        centre[axis] = sign * inner[axis]
                        centre[b] = sb.side * inner[b]
                        centre[c] = sc.side * inner[c]
                        let point = centre + r * normal
                        positions.append(point)
                        normals.append(normal)
                        uvs.append([0.5 + point[b] / (2 * half[b]), 0.5 + point[c] / (2 * half[c])])
                    }
                }
                // Wound by checking the first triangle against the face's outward direction.
                var order: [UInt32] = []
                for i in 0..<(n - 1) {
                    for j in 0..<(n - 1) {
                        let p00 = first + UInt32(i * n + j), p01 = p00 + 1
                        let p10 = p00 + UInt32(n), p11 = p10 + 1
                        order += [p00, p10, p11, p00, p11, p01]
                    }
                }
                let a = positions[Int(order[0])], bb = positions[Int(order[1])], cc = positions[Int(order[2])]
                var outward = SIMD3<Float>.zero
                outward[axis] = sign
                let faces = simd_dot(simd_cross(bb - a, cc - a), outward) > 0
                if !faces {
                    for t in stride(from: 0, to: order.count, by: 3) { order.swapAt(t + 1, t + 2) }
                }
                indices += order
            }
        }
        var descriptor = MeshDescriptor(name: "smoothBox")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
