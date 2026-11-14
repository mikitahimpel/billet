import CryptoKit
import DecorInterface
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
        let repo = Repo.root
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

        func models(_ root: Entity) -> Int {
            var count = 0
            root.forEachDescendant { if $0 is ModelEntity, $0.components.has(ModelComponent.self) { count += 1 } }
            return count
        }
        UserDefaults.standard.set("baked", forKey: BakedShell.labsKey)
        defer { UserDefaults.standard.removeObject(forKey: BakedShell.labsKey) }
        let city = CityRoomScene()
        #expect(city.isBaked)
        // The Bedroom's own furniture is the player's to move, so the stage builds it live whatever the shell is; only
        // what is built outside the stage counts against the baked path.
        #expect(models(city.pivot) - models(city.decorStage.root) < 70)
        UserDefaults.standard.removeObject(forKey: BakedShell.labsKey)
        let liveCity = CityRoomScene()
        #expect(!liveCity.isBaked)
        #expect(models(liveCity.pivot) > 150)
    }

    @Test func aRemoteBakedFlagTurnsItOnAndLabsTurnsItOff() throws {
        let flags = RemoteFlags(assignments: [Experiments.roomShell.key: "baked"])
        let remote = Self.defaults([RoomsChoice.remoteKey: try JSONEncoder().encode(flags)])
        #expect(BakedShell.resolved(remote) == .baked)
        remote.set("live", forKey: BakedShell.labsKey)
        #expect(BakedShell.resolved(remote) == .live)
    }

    /// The room's own furniture is the player's to move, so the floor of the baked shell is lit under each piece's home
    /// as it is beside it. A shell baked with the furniture standing keeps a black footprint where each piece was, and
    /// a piece moved off its home, or drawn a few centimetres from where the bake had it, shows that floor.
    @Test func theRoomShellsFloorIsLitUnderTheFurnituresHomes() async throws {
        let url = Repo.root.appending(path: "apps/ios/Nooki/Resources/Room/Room_shell.usdz")
        let shell = try await Entity(contentsOf: url)
        let floor = Self.floorTop(of: shell)
        #expect(floor.count > 10)
        let lightmap = try #require(StoredZip.entry(named: "room_lightmap.jpg", in: try Data(contentsOf: url)))
        let pixels = try #require(Pixels(jpeg: lightmap))
        var dark: [String] = []
        for item in DecorItem.baseItems(in: .living) where !item.isFlat {
            let home = try #require(item.base)
            let at = SIMD2(Float(DecorGrid.metres(home.u)), Float(DecorGrid.metres(home.v)))
            let uv = try #require(Self.uv(at: at, on: floor), "no floor under \(item.id)")
            let light = pixels.luminance(u: uv.x, v: uv.y)
            if light < 0.15 { dark.append("\(item.id) \(light)") }
        }
        #expect(dark.isEmpty, "the baked floor is black under: \(dark)")
    }

    private struct FloorTriangle {
        let points: [SIMD2<Float>]
        let uvs: [SIMD2<Float>]
    }

    /// The triangles on top of the floor's planks, in the shell's space, with their atlas coordinates.
    private static func floorTop(of shell: Entity) -> [FloorTriangle] {
        var found: [FloorTriangle] = []
        shell.forEachDescendant { entity in
            guard let model = entity.components[ModelComponent.self] else { return }
            // The file's root turns Blender's Z up to Y up, as it does under the room's pivot.
            let matrix = entity.transformMatrix(relativeTo: nil)
            for contentModel in model.mesh.contents.models {
                for part in contentModel.parts {
                    guard let uvs = part.textureCoordinates.map({ Array($0.elements) }) else { continue }
                    let positions = Array(part.positions.elements).map { p -> SIMD3<Float> in
                        let world = matrix * SIMD4(p, 1)
                        return SIMD3(world.x, world.y, world.z)
                    }
                    let indices =
                        part.triangleIndices.map { Array($0.elements) } ?? (0..<UInt32(positions.count)).map { $0 }
                    for i in stride(from: 0, to: indices.count - 2, by: 3) {
                        let corners = indices[i..<i + 3].map { positions[Int($0)] }
                        guard corners.allSatisfy({
                            abs($0.y - DecorStage.floorY) < 0.002 && abs($0.x) < 0.53 && abs($0.z) < 0.53
                        }) else { continue }
                        found.append(FloorTriangle(
                            points: corners.map { SIMD2($0.x, $0.z) }, uvs: indices[i..<i + 3].map { uvs[Int($0)] }))
                    }
                }
            }
        }
        return found
    }

    /// The atlas coordinates of the floor at `point`; a point in a seam between two planks takes the nearest plank.
    private static func uv(at point: SIMD2<Float>, on floor: [FloorTriangle]) -> SIMD2<Float>? {
        for nudge in [SIMD2<Float>.zero, [0, 0.01], [0, -0.01], [0.01, 0], [-0.01, 0]] {
            let p = point + nudge
            for triangle in floor {
                let (a, b, c) = (triangle.points[0], triangle.points[1], triangle.points[2])
                let v0 = b - a, v1 = c - a, v2 = p - a
                let d00 = simd_dot(v0, v0), d01 = simd_dot(v0, v1), d11 = simd_dot(v1, v1)
                let d20 = simd_dot(v2, v0), d21 = simd_dot(v2, v1)
                let denominator = d00 * d11 - d01 * d01
                guard abs(denominator) > 1e-12 else { continue }
                let v = (d11 * d20 - d01 * d21) / denominator
                let w = (d00 * d21 - d01 * d20) / denominator
                let u = 1 - v - w
                guard u >= -1e-4, v >= -1e-4, w >= -1e-4 else { continue }
                return triangle.uvs[0] * u + triangle.uvs[1] * v + triangle.uvs[2] * w
            }
        }
        return nil
    }
}

/// The files of a zip whose entries are stored, as a USDZ's are.
private enum StoredZip {
    static func entry(named suffix: String, in data: Data) -> Data? {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        let tail = max(0, bytes.count - 65_557)..<bytes.count - 21
        guard let end = tail.reversed().first(where: { u32($0) == 0x0605_4b50 }) else { return nil }
        var at = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard u32(at) == 0x0201_4b50 else { return nil }
            let method = u16(at + 10), size = u32(at + 24)
            let nameLength = u16(at + 28), extraLength = u16(at + 30), commentLength = u16(at + 32)
            let local = u32(at + 42)
            let name = String(decoding: bytes[at + 46..<at + 46 + nameLength], as: UTF8.self)
            at += 46 + nameLength + extraLength + commentLength
            guard name.hasSuffix(suffix) else { continue }
            guard method == 0, u32(local) == 0x0403_4b50 else { return nil }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            return Data(bytes[start..<start + size])
        }
        return nil
    }
}

/// An image's pixels, read back for a sample.
private struct Pixels {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init?(jpeg: Data) {
        guard let image = UIImage(data: jpeg)?.cgImage else { return nil }
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// 0 black to 1 white at a texture coordinate, the image's top row at v = 1.
    func luminance(u: Float, v: Float) -> Float {
        let x = min(max(Int(u * Float(width)), 0), width - 1)
        let y = min(max(Int((1 - v) * Float(height)), 0), height - 1)
        let at = (y * width + x) * 4
        return (Float(rgba[at]) + Float(rgba[at + 1]) + Float(rgba[at + 2])) / (3 * 255)
    }
}
