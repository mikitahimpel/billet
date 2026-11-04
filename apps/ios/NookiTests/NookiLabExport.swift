import Foundation
import RealityKit
import Testing
import UIKit

@testable import Billet

/// Writes Nooki's three rooms as glTF for the local web lab, built by the app's own scene code: for each room
/// `<room>.glb` holds every model under the room's pivot but Mochi, in metres (y up), and `<room>.json` its lights,
/// ambient, camera framing and Mochi's spot and route. The City room is also written at every other hour of its day
/// cycle (lights, glows, ambient and the town picture in the window). Runs only when `NOOKI_LAB_EXPORT` names a
/// directory to write into (`TEST_RUNNER_NOOKI_LAB_EXPORT` through xcodebuild).
@Suite struct NookiLabExport {
    private nonisolated static let directory = ProcessInfo.processInfo.environment["NOOKI_LAB_EXPORT"]

    @Test(.enabled(if: directory != nil), .timeLimit(.minutes(5)))
    func export() async throws {
        let directory = URL(fileURLWithPath: try #require(Self.directory), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let diorama = DioramaScene()
        try await Self.settle(diorama) { diorama.isReady }
        try Self.write(diorama, name: "diorama", ambient: Self.warmAmbient, into: directory)

        let board = BoardRoomScene()
        try await Self.settle(board) { board.walker != nil }
        var boardExtra: [String: Any] = [:]
        if let sheet = Self.drawHere().pngData() {
            try sheet.write(to: directory.appending(path: "board-drawhere.png"))
            boardExtra["textures"] = ["board-drawhere.png"]
        }
        try Self.write(board, name: "board", ambient: Self.warmAmbient, extra: boardExtra, into: directory)

        try await exportCity(into: directory)
    }

    /// The City room at its live hour, then through the showcase's day cycle (14 s a day) to each even hour.
    private func exportCity(into directory: URL) async throws {
        var hour = Daylight.localHour()
        let city = CityRoomScene()
        try await Self.settle(city) { city.walker != nil }
        // The glows and the town are set by the hour; the GLB is written at the live hour and each hour lists what
        // changes from it.
        let writer = try Self.write(city, name: "city", ambient: Self.cityAmbient(hour), into: directory)
        try #require(city.roomShowcase.first).start()
        var hours: [[String: Any]] = []
        for target in stride(from: 0, to: 24, by: 2).map(Float.init).sorted(by: { Self.ahead(hour, $0) < Self.ahead(hour, $1) }) {
            var left = Self.ahead(hour, target) * 14 / 24
            while left > 0 {
                let dt = min(left, 1 / 30)
                city.tick(dt)
                left -= dt
            }
            hour = target
            // Bulbs and shades pulse in tick; a frame with no time keeps them where the hour set them.
            city.tick(0)
            let light = Daylight.sample(hour)
            let picture = "city-town-\(Int(hour)).png"
            try TownPicture.image(light).pngData()?.write(to: directory.appending(path: picture))
            var lights: [[String: Any]] = []
            Self.lights(in: city.root, root: city.root, into: &lights)
            hours.append([
                "hour": hour, "lights": lights, "glows": writer.glows(), "ambient": Self.cityAmbient(hour),
                "town": picture, "darkness": light.darkness,
            ])
        }
        hours.sort { ($0["hour"] as! Float) < ($1["hour"] as! Float) }
        let json = try JSONSerialization.data(withJSONObject: ["hours": hours], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appending(path: "city-hours.json"))
    }

    /// Hours from `hour` forward to `target` on the 24 h clock.
    private static func ahead(_ hour: Float, _ target: Float) -> Float {
        (target - hour + 24).truncatingRemainder(dividingBy: 24)
    }

    /// Waits for the room's async pieces (furniture, Mochi, the ambient bake), then runs a few frames.
    private static func settle(_ room: CatRoom, until ready: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(60)
        while !ready(), Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(ready())
        try await Task.sleep(for: .seconds(1))
        for _ in 0..<5 { room.tick(1 / 60) }
    }

    private static let warmAmbient: [String: Any] = ["top": "#FFE7C4", "bottom": "#B97A45", "exponent": -0.4]

    /// The City's ambient as its live clock bakes it: warm, tinted by the sky, as bright as the hour.
    private static func cityAmbient(_ hour: Float) -> [String: Any] {
        let light = Daylight.sample(hour)
        let top = simd_mix(Daylight.rgb(0xFFE7C4), light.top, SIMD3(repeating: 0.3))
        let bottom = simd_mix(Daylight.rgb(0xB97A45), light.horizon, SIMD3(repeating: 0.25))
        return [
            "top": Daylight.color(top).labHex, "bottom": Daylight.color(bottom).labHex,
            "exponent": log2(max(light.env, 0.05) / 0.85) - 0.4,
        ]
    }

    @discardableResult
    private static func write(
        _ room: CatRoom, name: String, ambient: [String: Any], extra: [String: Any] = [:], into directory: URL
    ) throws -> GLBWriter {
        var writer = GLBWriter()
        for child in room.pivot.children where child !== room.catGroup {
            writer.addPiece(child, relativeTo: room.root)
        }
        try writer.data().write(to: directory.appending(path: "\(name).glb"))

        var lights: [[String: Any]] = []
        Self.lights(in: room.root, root: room.root, into: &lights)
        let framing = room.framing
        var info: [String: Any] = [
            "room": name,
            "glb": "\(name).glb",
            "lights": lights,
            "ambient": ambient,
            // DioramaView: a 22° camera looking from target + direction * distance, distance far + (near - far) * zoom,
            // the target eased toward Mochi's head by the zoom (0.25 at rest).
            "camera": [
                "target": framing.target.array, "direction": framing.direction.array, "far": framing.far,
                "near": framing.near, "zoom": 0.25, "fieldOfView": 22, "focus": room.catFocus.array,
                "yawLimit": room.yawLimit,
            ],
            "bloom": ["strength": 0.35, "threshold": 1.1],
            "textured": writer.textured,
        ]
        if let cat = Self.cat(room) { info["cat"] = cat }
        info.merge(extra) { $1 }
        let json = try JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appending(path: "\(name).json"))
        return writer
    }

    /// Mochi's group (the standing splat's origin), its scale, the seated splat's mount and her route out and home.
    private static func cat(_ room: CatRoom) -> [String: Any]? {
        guard let walker = room.walker else { return nil }
        let group = room.catGroup
        let model = group.children.first?.children.first
        let fields = Dictionary(
            Mirror(reflecting: walker).children.compactMap { c in c.label.map { ($0, c.value) } }) { a, _ in a }
        var out: [String: Any] = [
            "position": group.position(relativeTo: room.root).array,
            "matrix": group.transformMatrix(relativeTo: room.root).flat,
            "scale": model?.scale.x ?? 1,
            "mount": walker.seated.mount.array,
            "wandering": walker.wandering,
        ]
        if let yaw = fields["homeYaw"] as? Float { out["homeYaw"] = yaw }
        if let home = fields["home"] as? SIMD3<Float> { out["home"] = home.array }
        if let main = walker.main {
            out["route"] = [
                "rest": main.rest,
                "path": main.path.map { ["at": $0.at.array, "move": String(describing: $0.move)] },
            ]
        }
        return out
    }

    /// BoardRoomScene's "draw here" sheet, drawn again: the room's textures don't read back from RealityKit.
    private static func drawHere() -> UIImage {
        let size = CGSize(width: 512, height: 170)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let ink = UIColor(hex: 0x5B3A28)
            let font = UIFont(name: "Noteworthy-Bold", size: 84) ?? .systemFont(ofSize: 84, weight: .bold)
            ("draw here" as NSString).draw(at: CGPoint(x: 6, y: 40), withAttributes: [.font: font, .foregroundColor: ink])
            ink.setStroke()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: 344, y: 138))
            arrow.addQuadCurve(to: CGPoint(x: 470, y: 70), controlPoint: CGPoint(x: 470, y: 146))
            arrow.move(to: CGPoint(x: 448, y: 92))
            arrow.addLine(to: CGPoint(x: 470, y: 70))
            arrow.addLine(to: CGPoint(x: 488, y: 94))
            arrow.lineWidth = 7
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            arrow.stroke()
        }
    }

    fileprivate static func lights(in entity: Entity, root: Entity, into out: inout [[String: Any]]) {
        guard entity.isEnabled else { return }
        let world = entity.transformMatrix(relativeTo: root)
        let position = [world.columns.3.x, world.columns.3.y, world.columns.3.z]
        // RealityKit lights shine down their entity's -z.
        let forward = -simd_normalize(SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
        let base: [String: Any] = [
            "name": entity.name, "position": position, "direction": forward.array,
        ]
        if let point = entity.components[PointLightComponent.self] {
            out.append(base.merging([
                "type": "point", "colour": point.color.labHex, "intensity": point.intensity,
                "radius": point.attenuationRadius, "falloff": point.attenuationFalloffExponent,
            ]) { $1 })
        }
        if let spot = entity.components[SpotLightComponent.self] {
            out.append(base.merging([
                "type": "spot", "colour": spot.color.labHex, "intensity": spot.intensity,
                "radius": spot.attenuationRadius, "inner": spot.innerAngleInDegrees, "outer": spot.outerAngleInDegrees,
                "shadow": entity.components.has(SpotLightComponent.Shadow.self),
            ]) { $1 })
        }
        if let sun = entity.components[DirectionalLightComponent.self] {
            out.append(base.merging([
                "type": "directional", "colour": sun.color.labHex, "intensity": sun.intensity,
                "shadow": entity.components.has(DirectionalLightComponent.Shadow.self),
            ]) { $1 })
        }
        for child in entity.children { lights(in: child, root: root, into: &out) }
    }
}

/// A minimal glTF 2.0 binary writer: positions, normals, texture coordinates and triangles, with each material's
/// colour, roughness, metalness, emission and opacity. Textures don't read back from RealityKit on the Simulator, so
/// a textured material is only marked (`extras.textured`) and its node listed in `textured`.
private struct GLBWriter {
    private var buffer = Data()
    private var views: [[String: Any]] = []
    private var accessors: [[String: Any]] = []
    private var meshes: [[String: Any]] = []
    private var materials: [[String: Any]] = []
    private var nodes: [[String: Any]] = []
    private var pieces: [Int] = []
    /// Every model's node index and entity, to read their glows again later.
    private var models: [(Int, Entity)] = []
    private(set) var textured: [[String: Any]] = []

    mutating func addPiece(_ piece: Entity, relativeTo root: Entity) {
        var children: [Int] = []
        collect(piece, root: root, into: &children)
        guard !children.isEmpty else { return }
        nodes.append(["name": piece.name.isEmpty ? "piece" : piece.name, "children": children])
        pieces.append(nodes.count - 1)
    }

    /// Each model's emission now, by node index: what the lab sets on that node's materials.
    func glows() -> [String: Float] {
        var out: [String: Float] = [:]
        for (index, entity) in models {
            guard let model = entity.components[ModelComponent.self] else { continue }
            let strength = model.materials.compactMap { ($0 as? PhysicallyBasedMaterial)?.emissiveIntensity }.max() ?? 0
            if strength > 0 { out[String(index)] = strength }
        }
        return out
    }

    private mutating func collect(_ entity: Entity, root: Entity, into out: inout [Int]) {
        guard entity.isEnabled else { return }
        if let model = entity.components[ModelComponent.self] {
            let world = entity.transformMatrix(relativeTo: root)
            if let mesh = addMesh(model) {
                var node: [String: Any] = ["name": entity.name, "mesh": mesh, "matrix": world.flat]
                if model.materials.contains(where: { Self.hasTexture($0) }) {
                    node["extras"] = ["textured": true]
                    textured.append(["node": nodes.count, "name": entity.name, "position": world.columns.3.xyz.array])
                }
                nodes.append(node)
                models.append((nodes.count - 1, entity))
                out.append(nodes.count - 1)
            }
        }
        for child in entity.children { collect(child, root: root, into: &out) }
    }

    private mutating func addMesh(_ model: ModelComponent) -> Int? {
        let contents = model.mesh.contents
        let firstMaterial = materials.count
        for material in model.materials { materials.append(Self.material(material)) }
        var primitives: [[String: Any]] = []
        for instance in contents.instances {
            guard let source = contents.models[instance.model] else { continue }
            let t = instance.transform
            for part in source.parts {
                let positions = part.positions.elements.map { p -> SIMD3<Float> in (t * SIMD4(p, 1)).xyz }
                guard !positions.isEmpty, let indices = part.triangleIndices?.elements else { continue }
                var attributes: [String: Int] = [
                    "POSITION": addAccessor(positions.flatMap(\.array), type: "VEC3", bounds: positions)
                ]
                if let normals = part.normals?.elements {
                    let turned = normals.map { n in simd_normalize((t * SIMD4(n, 0)).xyz) }
                    attributes["NORMAL"] = addAccessor(turned.flatMap(\.array), type: "VEC3")
                }
                if let uvs = part.textureCoordinates?.elements {
                    attributes["TEXCOORD_0"] = addAccessor(uvs.flatMap { [$0.x, 1 - $0.y] }, type: "VEC2")
                }
                var primitive: [String: Any] = ["attributes": attributes, "indices": addIndices(indices)]
                if !model.materials.isEmpty {
                    primitive["material"] = firstMaterial + min(part.materialIndex, model.materials.count - 1)
                }
                primitives.append(primitive)
            }
        }
        guard !primitives.isEmpty else { return nil }
        meshes.append(["primitives": primitives])
        return meshes.count - 1
    }

    private static func hasTexture(_ material: any RealityKit.Material) -> Bool {
        if let pbr = material as? PhysicallyBasedMaterial { return pbr.baseColor.texture != nil }
        if let simple = material as? SimpleMaterial { return simple.color.texture != nil }
        if let flat = material as? UnlitMaterial { return flat.color.texture != nil }
        return false
    }

    private static func material(_ material: any RealityKit.Material) -> [String: Any] {
        var colour = UIColor.white
        var roughness: Float = 0.8
        var metallic: Float = 0
        var emissive = UIColor.black
        var emission: Float = 0
        var opacity: Float = 1
        var unlit = false
        var kind = "other"
        if let pbr = material as? PhysicallyBasedMaterial {
            kind = "pbr"
            colour = pbr.baseColor.tint
            roughness = pbr.roughness.scale
            metallic = pbr.metallic.scale
            emissive = pbr.emissiveColor.color
            emission = pbr.emissiveIntensity
            if case .transparent(let o) = pbr.blending { opacity = o.scale }
        } else if let simple = material as? SimpleMaterial {
            kind = "simple"
            colour = simple.color.tint
        } else if let flat = material as? UnlitMaterial {
            kind = "unlit"
            colour = flat.color.tint
            unlit = true
            if case .transparent(let o) = flat.blending { opacity = o.scale }
        }
        let c = colour.labLinear
        let e = emissive.labLinear
        var extras: [String: Any] = ["kind": kind, "emissiveIntensity": emission]
        if hasTexture(material) { extras["textured"] = true }
        var out: [String: Any] = [
            "name": kind,
            "pbrMetallicRoughness": [
                "baseColorFactor": [c[0], c[1], c[2], c[3] * opacity], "roughnessFactor": roughness,
                "metallicFactor": metallic,
            ],
            "extras": extras,
        ]
        if emission > 0, e.prefix(3).contains(where: { $0 > 0 }) {
            out["emissiveFactor"] = [e[0], e[1], e[2]]
            out["extensions"] = ["KHR_materials_emissive_strength": ["emissiveStrength": emission]]
        }
        if c[3] * opacity < 0.999 || (opacity < 1) { out["alphaMode"] = "BLEND" }
        if case let pbr as PhysicallyBasedMaterial = material, case .transparent = pbr.blending { out["alphaMode"] = "BLEND" }
        if unlit { out["extensions"] = ["KHR_materials_unlit": [String: Any]()] }
        return out
    }

    private mutating func addView(_ bytes: Data, target: Int?) -> Int {
        while buffer.count % 4 != 0 { buffer.append(0) }
        var view: [String: Any] = ["buffer": 0, "byteOffset": buffer.count, "byteLength": bytes.count]
        if let target { view["target"] = target }
        views.append(view)
        buffer.append(bytes)
        return views.count - 1
    }

    private mutating func addAccessor(_ floats: [Float], type: String, bounds: [SIMD3<Float>]? = nil) -> Int {
        let width = type == "VEC3" ? 3 : 2
        let view = addView(floats.withUnsafeBufferPointer { Data(buffer: $0) }, target: 34962)
        var accessor: [String: Any] = [
            "bufferView": view, "componentType": 5126, "count": floats.count / width, "type": type,
        ]
        if let bounds {
            let low = bounds.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
            let high = bounds.reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
            accessor["min"] = low.array
            accessor["max"] = high.array
        }
        accessors.append(accessor)
        return accessors.count - 1
    }

    private mutating func addIndices(_ indices: [UInt32]) -> Int {
        let view = addView(indices.withUnsafeBufferPointer { Data(buffer: $0) }, target: 34963)
        accessors.append(["bufferView": view, "componentType": 5125, "count": indices.count, "type": "SCALAR"])
        return accessors.count - 1
    }

    func data() throws -> Data {
        var padded = buffer
        while padded.count % 4 != 0 { padded.append(0) }
        let json: [String: Any] = [
            "asset": ["version": "2.0", "generator": "billet NookiLabExport"],
            "extensionsUsed": ["KHR_materials_emissive_strength", "KHR_materials_unlit"],
            "scene": 0,
            "scenes": [["nodes": pieces]],
            "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accessors,
            "bufferViews": views, "buffers": [["byteLength": padded.count]],
        ]
        var text = try JSONSerialization.data(withJSONObject: json)
        while text.count % 4 != 0 { text.append(0x20) }
        var out = Data()
        func word(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { out.append(contentsOf: $0) } }
        word(0x4654_6C67)
        word(2)
        word(UInt32(12 + 8 + text.count + 8 + padded.count))
        word(UInt32(text.count))
        word(0x4E4F_534A)
        out.append(text)
        word(UInt32(padded.count))
        word(0x004E_4942)
        out.append(padded)
        return out
    }
}

extension UIColor {
    /// sRGB components as linear light, with alpha.
    fileprivate var labLinear: [Float] {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ v: CGFloat) -> Float {
            let x = Float(max(0, min(1, v)))
            return x <= 0.04045 ? x / 12.92 : powf((x + 0.055) / 1.055, 2.4)
        }
        return [lin(r), lin(g), lin(b), Float(a)]
    }

    fileprivate var labHex: String {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let v = [r, g, b].map { Int((max(0, min(1, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}

extension SIMD3 where Scalar == Float {
    fileprivate var array: [Float] { [x, y, z] }
}

extension SIMD4 where Scalar == Float {
    fileprivate var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

extension simd_float4x4 {
    fileprivate var flat: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
}
