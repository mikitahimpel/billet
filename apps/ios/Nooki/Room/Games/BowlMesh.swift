import RealityKit

/// A bowl you can see into: an open shell of a given depth, so what is poured in shows from above the rim. Built once
/// per size and shared; two parts, the outside (wall, underside, rim) and the inside (wall and floor), each to take its
/// own material.
enum BowlMesh {
    private struct Part {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        mutating func add(_ points: [SIMD3<Float>], _ normal: [SIMD3<Float>], _ triangles: [UInt32]) {
            let base = UInt32(positions.count)
            positions += points
            normals += normal
            indices += triangles.map { $0 + base }
        }
    }

    static func make(outer: Float, inner: Float, height: Float, floor: Float, sides: Int = 40) -> MeshResource? {
        var shell = Part(), cavity = Part()
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * .pi, a1 = Float(i + 1) / Float(sides) * 2 * .pi
            let r0 = SIMD3<Float>(cos(a0), 0, sin(a0)), r1 = SIMD3<Float>(cos(a1), 0, sin(a1))
            let up = SIMD3<Float>(0, 1, 0)
            func at(_ r: SIMD3<Float>, _ radius: Float, _ y: Float) -> SIMD3<Float> { r * radius + [0, y, 0] }
            shell.add([at(r0, outer, 0), at(r1, outer, 0), at(r1, outer, height), at(r0, outer, height)],
                      [r0, r1, r1, r0], [0, 2, 1, 0, 3, 2])
            shell.add([at(.zero, 0, 0), at(r0, outer, 0), at(r1, outer, 0)], Array(repeating: -up, count: 3), [0, 1, 2])
            shell.add([at(r0, inner, height), at(r1, inner, height), at(r1, outer, height), at(r0, outer, height)],
                      Array(repeating: up, count: 4), [0, 1, 2, 0, 2, 3])
            cavity.add([at(r0, inner, floor), at(r1, inner, floor), at(r1, inner, height), at(r0, inner, height)],
                       [-r0, -r1, -r1, -r0], [0, 1, 2, 0, 2, 3])
            cavity.add([at(.zero, 0, floor), at(r0, inner, floor), at(r1, inner, floor)], Array(repeating: up, count: 3),
                       [0, 2, 1])
        }
        let descriptors = [shell, cavity].enumerated().map { index, part -> MeshDescriptor in
            var descriptor = MeshDescriptor(name: index == 0 ? "bowl-shell" : "bowl-cavity")
            descriptor.positions = MeshBuffers.Positions(part.positions)
            descriptor.normals = MeshBuffers.Normals(part.normals)
            descriptor.primitives = .triangles(part.indices)
            return descriptor
        }
        return try? MeshResource.generate(from: descriptors)
    }
}
