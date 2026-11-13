import RealityKit
import Testing

@testable import Billet

/// The lean box and sphere meshes: the same bounds as RealityKit's, faces turned outward, and far fewer triangles.
@MainActor
struct SmoothMeshTests {
    private struct Triangle {
        var a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>
    }

    private func triangles(of mesh: MeshResource) -> [Triangle] {
        var out: [Triangle] = []
        let contents = mesh.contents
        for instance in contents.instances {
            guard let model = contents.models[instance.model] else { continue }
            for part in model.parts {
                let points = Array(part.positions.elements)
                let indices = part.triangleIndices.map { Array($0.elements) } ?? (0..<UInt32(points.count)).map { $0 }
                for i in stride(from: 0, to: indices.count - 2, by: 3) {
                    out.append(Triangle(a: points[Int(indices[i])], b: points[Int(indices[i + 1])], c: points[Int(indices[i + 2])]))
                }
            }
        }
        return out
    }

    private func facesOutward(_ mesh: MeshResource) -> Bool {
        let centre = mesh.bounds.center
        return triangles(of: mesh).allSatisfy { t in
            let normal = simd_cross(t.b - t.a, t.c - t.a)
            return simd_length(normal) < 1e-12 || simd_dot(normal, (t.a + t.b + t.c) / 3 - centre) > 0
        }
    }

    @Test(arguments: [Float(0), 0.0005, 0.004, 0.012, 0.03, 0.2])
    func aBoxHasTheSizeItWasAskedForAndFacesOutward(radius: Float) throws {
        let mesh = try #require(SmoothBox.mesh(width: 0.5, height: 0.1, depth: 0.3, radius: radius))
        #expect(simd_length(mesh.bounds.extents - [0.5, 0.1, 0.3]) < 1e-4)
        #expect(facesOutward(mesh))
    }

    @Test func aBoxCostsWhatItsRadiusCanShow() throws {
        let square = triangles(of: try #require(SmoothBox.mesh(width: 0.5, height: 0.1, depth: 0.3, radius: 0)))
        let fine = triangles(of: try #require(SmoothBox.mesh(width: 0.5, height: 0.1, depth: 0.3, radius: 0.004)))
        let wide = triangles(of: try #require(SmoothBox.mesh(width: 0.5, height: 0.1, depth: 0.3, radius: 0.03)))
        #expect(square.count == 12)
        #expect(fine.count == 108)
        #expect(wide.count == 300)
        // RealityKit's rounded box is 13,068 triangles at every radius.
        #expect(wide.count * 40 < 13_068)
    }

    @Test func moreFacetsForAWiderFillet() {
        #expect(SmoothBox.facets(radius: 0) == 0)
        #expect(SmoothBox.facets(radius: 0.002) == 2)
        #expect(SmoothBox.facets(radius: 0.03) >= SmoothBox.facets(radius: 0.01))
        #expect(SmoothBox.facets(radius: 0.03).isMultiple(of: 2))
    }

    @Test func aSphereIsUnitSizedAndFacesOutward() throws {
        for segments in [12, 20, 64] {
            let mesh = try #require(SmoothSphere.mesh(segments: segments))
            #expect(simd_length(mesh.bounds.extents - [2, 2, 2]) < 0.05)
            #expect(facesOutward(mesh))
            #expect(triangles(of: mesh).count == segments * (segments / 2 - 1) * 2)
        }
    }

    @Test func aSmallSphereGetsFewerSegmentsThanALargeOne() {
        #expect(SmoothSphere.segments(radius: 0.001) == 12)
        #expect(SmoothSphere.segments(radius: 0.01) < SmoothSphere.segments(radius: 0.06))
        #expect(SmoothSphere.segments(radius: 5) == 64)
    }
}
