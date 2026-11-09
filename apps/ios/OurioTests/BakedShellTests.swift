import CryptoKit
import Foundation
import RealityKit
import Testing
import UIKit
import WidgetBridge
@testable import Billet

/// The baked room shells (scripts/bake-room): the export the bake reads, and a check that the shells in the app were
/// baked from the rooms as the code builds them now.
@MainActor
struct BakedShellTests {
    private struct Part {
        let material: String
        let color: [Double]
        let roughness: Double
        let matrix: [Double]
        let shape: String
        let size: [Double]
        /// A mesh no shape describes, in the pivot's space.
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
        let indices: [UInt32]
    }

    private static func defaults(_ values: [String: Any]) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "baked-shell-\(UUID().uuidString)")!
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    private static func round(_ value: Float, _ places: Double = 1e5) -> Double { (Double(value) * places).rounded() / places }

    /// Collects a room's tagged static parts, in the pivot's space.
    private static func parts(of room: CatRoom) -> [Part] {
        var parts: [Part] = []
        room.pivot.forEachDescendant { entity in
            guard let tag = entity.components[ShellPart.self], let model = entity as? ModelEntity,
                  let component = model.model, let material = component.materials.first as? PhysicallyBasedMaterial
            else { return }
            let matrix = entity.transformMatrix(relativeTo: room.pivot)
            var rgba: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            material.baseColor.tint.getRed(&rgba.0, green: &rgba.1, blue: &rgba.2, alpha: &rgba.3)
            let color = [rgba.0, rgba.1, rgba.2].map { Double($0) }
            let roughness = Double(material.roughness.scale)
            let key = String(format: "%.3f-%.3f-%.3f-%.2f", color[0], color[1], color[2], roughness)
            let flat = (0..<4).flatMap { c in (0..<4).map { r in Double(matrix[c][r]) } }
            switch tag.shape {
            case .box(let size, let radius):
                parts.append(Part(material: key, color: color, roughness: roughness, matrix: flat, shape: "box",
                                  size: [size.x, size.y, size.z, radius].map(Double.init), positions: [], normals: [], indices: []))
            case .sphere, .cylinder:
                let name = if case .sphere = tag.shape { "sphere" } else { "cylinder" }
                parts.append(Part(material: key, color: color, roughness: roughness, matrix: flat, shape: name,
                                  size: [], positions: [], normals: [], indices: []))
            case nil:
                let normalMatrix = simd_transpose(simd_inverse(simd_float3x3(
                    SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                    SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                    SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))))
                for contentModel in component.mesh.contents.models {
                    for part in contentModel.parts {
                        let positions = Array(part.positions.elements).map { p -> SIMD3<Float> in
                            let world = matrix * SIMD4(p, 1)
                            return SIMD3(world.x, world.y, world.z)
                        }
                        let normals = (part.normals.map { Array($0.elements) } ?? []).map { simd_normalize(normalMatrix * $0) }
                        parts.append(Part(material: key, color: color, roughness: roughness, matrix: flat, shape: "mesh",
                                          size: [], positions: positions, normals: normals,
                                          indices: part.triangleIndices.map { Array($0.elements) } ?? []))
                    }
                }
            }
        }
        return parts
    }

    /// What the bake was made from: each part's material, shape and transform.
    private static func fingerprint(_ parts: [Part]) -> String {
        let lines = parts.map { part in
            ([part.material, part.shape] + (part.matrix + part.size).map { String(format: "%.4f", $0) })
                .joined(separator: " ")
        }
        return SHA256.hash(data: Data(lines.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The scene for the Blender bake: the room's parts and their materials, in the pivot's space.
    private static func scene(_ parts: [Part]) throws -> Data {
        let entries: [[String: Any]] = parts.map { part in
            var entry: [String: Any] = [
                "material": part.material, "color": part.color, "roughness": part.roughness,
                "shape": part.shape, "matrix": part.matrix.map { ($0 * 1e6).rounded() / 1e6 },
            ]
            if !part.size.isEmpty { entry["size"] = part.size }
            if part.shape == "mesh" {
                entry["positions"] = part.positions.flatMap { [Self.round($0.x), Self.round($0.y), Self.round($0.z)] }
                entry["normals"] = part.normals.flatMap { [Self.round($0.x, 1e4), Self.round($0.y, 1e4), Self.round($0.z, 1e4)] }
                entry["indices"] = part.indices
            }
            return entry
        }
        return try JSONSerialization.data(withJSONObject: ["parts": entries], options: [.sortedKeys])
    }

    private static func room(_ name: String) -> CatRoom {
        UserDefaults.standard.set(true, forKey: BakedShell.exportKey)
        defer { UserDefaults.standard.removeObject(forKey: BakedShell.exportKey) }
        return name == "Room_shell" ? DioramaScene() : CityRoomScene()
    }

    private static let rooms = ["Room_shell", "City_shell"]

    /// `TEST_RUNNER_BAKE_EXPORT_DIR=<dir> xcodebuild test -only-testing OurioTests/BakedShellTests/export` writes
    /// each room's `<name>.json` and `<name>.sha`; without the variable it does nothing.
    @Test func export() throws {
        guard let directory = ProcessInfo.processInfo.environment["BAKE_EXPORT_DIR"] else { return }
        for name in Self.rooms {
            let parts = Self.parts(of: Self.room(name))
            #expect(!parts.isEmpty)
            try Self.scene(parts).write(to: URL(fileURLWithPath: directory).appending(path: "\(name).json"))
            try Self.fingerprint(parts).write(
                to: URL(fileURLWithPath: directory).appending(path: "\(name).sha"), atomically: true, encoding: .utf8)
        }
    }

    /// The shells that ship were baked from the rooms as built now. Fails after a change to a room's static boxes
    /// until `scripts/bake-room/bake.sh` has been run again.
    @Test func theBakedShellsAreUpToDate() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let recorded = try JSONDecoder().decode(
            [String: String].self, from: Data(contentsOf: repo.appending(path: "scripts/bake-room/sources.json")))
        for name in Self.rooms {
            let parts = Self.parts(of: Self.room(name))
            #expect(recorded[name] == Self.fingerprint(parts), "\(name) is stale: run scripts/bake-room/bake.sh")
        }
    }

    /// With the baked shell on, the static boxes are not built: only the glowing parts and the live ones are.
    @Test func theBakedPathBuildsOnlyTheLiveParts() throws {
        let live = Self.defaults([:])
        let baked = Self.defaults([BakedShell.labsKey: "baked"])
        #expect(BakedShell.resolved(live) == .live)
        #expect(BakedShell.resolved(baked) == .baked)

        func models(_ room: CatRoom) -> Int {
            var count = 0
            room.pivot.forEachDescendant { if $0 is ModelEntity, $0.components.has(ModelComponent.self) { count += 1 } }
            return count
        }
        UserDefaults.standard.set("baked", forKey: BakedShell.labsKey)
        defer { UserDefaults.standard.removeObject(forKey: BakedShell.labsKey) }
        let city = CityRoomScene()
        #expect(city.isBaked)
        #expect(models(city) < 70)
        UserDefaults.standard.removeObject(forKey: BakedShell.labsKey)
        let liveCity = CityRoomScene()
        #expect(!liveCity.isBaked)
        #expect(models(liveCity) > 150)
    }

    @Test func aRemoteBakedFlagTurnsItOnAndLabsTurnsItOff() throws {
        let flags = RemoteFlags(assignments: [Experiments.roomShell.key: "baked"])
        let remote = Self.defaults([RoomsChoice.remoteKey: try JSONEncoder().encode(flags)])
        #expect(BakedShell.resolved(remote) == .baked)
        remote.set("live", forKey: BakedShell.labsKey)
        #expect(BakedShell.resolved(remote) == .live)
    }
}
