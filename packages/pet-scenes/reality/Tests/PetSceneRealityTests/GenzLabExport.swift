#if os(macOS)
  import AppKit
  import ImageIO
  import Metal
  import UniformTypeIdentifiers
  import Foundation
  import Pet
  import RealityKit
  import SwiftUI
  import Testing

  @testable import PetSceneReality

  /// Writes the built Window Seat room as glTF for the web lab: `room-<furniture>.glb` holds every
  /// model of the room in scene units (y up), one node per piece under the room, and
  /// `lights-<furniture>.json` the lights each lighting preset turns on, the home camera and the
  /// ambient. Runs only when `GENZ_LAB_EXPORT` names a directory to write into.
  @MainActor
  @Suite struct GenzLabExport {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_LAB_EXPORT"] != nil))
    func export() async throws {
      let directory = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_LAB_EXPORT"]),
        isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for furniture in RoomFurniture.allCases {
        let layout = GenzLayout.of(furniture)
        let room = GenzRoomCache(suite: "genz-lab-\(UUID())").room(layout)
        // As GenzRenderShots lights it: on screen and updating, so the opening brings the lights up.
        room.fit(to: CGSize(width: 393, height: 852))
        room.setLighting(.standard)
        room.setOnScreen(true, in: UUID())
        room.startUpdates()
        room.startBuilding()
        let deadline = Date.now.addingTimeInterval(120)
        while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(room.isBuilt)
        try await Task.sleep(for: .seconds(GenzOpening.length + 1))

        var writer = GLBWriter()
        for child in room.room.children where child !== room.catHolder {
          writer.addPiece(child, relativeTo: room.root)
        }
        try writer.data().write(to: directory.appending(path: "room-\(furniture).glb"))

        // The note's paper as the room draws it before the pair has drawn anything, and the flat
        // street the app paints behind the window: the room's textures don't read back from
        // RealityKit, so both are drawn again here the way the app draws them.
        let panel = layout.note
        if let note = GenzTextures.note(
          drawing: nil, paper: layout.paper, aspect: CGFloat(panel.height / panel.width),
          corners: true)
        {
          try Self.png(note).write(to: directory.appending(path: "note-\(furniture).png"))
        }
        let window = layout.window.map(\.scene)
        let (across, down) = Self.windowEdges(window)
        let viewState = room.screen.viewState(at: .now)
        if let street = await Self.street(viewState, aspect: CGFloat(down / across)) {
          try Self.png(street).write(to: directory.appending(path: "street-\(furniture).png"))
        }

        var presets: [String: Any] = [:]
        defer { room.setOnScreen(false, in: UUID()) }
        for preset in RoomLighting.allCases {
          room.setLighting(preset)
          try await Task.sleep(for: .seconds(2))
          var lights: [[String: Any]] = []
          Self.lights(in: room.root, root: room.root, into: &lights)
          presets[preset.rawValue] = lights
        }
        let home = layout.camera
        let info: [String: Any] = [
          "furniture": furniture.rawValue,
          "standardLighting": RoomLighting.standard.rawValue,
          "camera": [
            "target": [home.target.x, home.target.y, home.target.z], "yaw": home.yaw,
            "pitch": home.pitch, "distance": home.distance, "fieldOfView": home.fieldOfView,
            "aspect": home.aspect,
          ],
          "cat": [
            "spot": layout.cat.spot.scene.array, "heading": layout.cat.heading,
            "length": layout.cat.length,
          ],
          "ambient": [
            "top": layout.ambient.top.hex, "bottom": layout.ambient.bottom.hex,
            "exponent": layout.ambient.exponent,
          ],
          "lights": presets,
          "note": ["name": GenzRoom.noteName, "image": "note-\(furniture).png"],
          "window": [
            "corners": window.map(\.array), "image": "street-\(furniture).png",
            "view": String(describing: viewState.view), "hour": String(describing: viewState.hour),
          ],
        ]
        let json = try JSONSerialization.data(
          withJSONObject: info, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appending(path: "lights-\(furniture).json"))
      }
    }

    /// The window's width and height in scene units: of its first two edges, the level one is
    /// across.
    private static func windowEdges(_ corners: [SIMD3<Float>]) -> (Float, Float) {
      guard corners.count == 4 else { return (1, 1) }
      let a = corners[1] - corners[0]
      let b = corners[2] - corners[1]
      return abs(a.y) < abs(b.y) ? (simd_length(a), simd_length(b)) : (simd_length(b), simd_length(a))
    }

    /// The flat window view as the app paints it behind the room, filling an image the window's
    /// shape, as ViewThumbnail draws a shop thumbnail.
    private static func street(_ state: WindowViewState, aspect: CGFloat) async -> CGImage? {
      let width: CGFloat = 640
      let height = (width * aspect).rounded()
      let corners = [
        CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: width, y: height),
        CGPoint(x: 0, y: height),
      ]
      var shown = state
      shown.window = corners
      shown.home = corners
      shown.inDepth = false
      let plates = ViewPlateCache()
      let content = NativeWindowView(state: shown, plates: plates)
        .frame(width: width, height: height)
        .environment(\.displayScale, 2)
      func snapshot() -> CGImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        return renderer.cgImage
      }
      // The first pass asks for the plates; they are painted on the next turns of the main actor.
      _ = snapshot()
      let deadline = ContinuousClock.now + .seconds(5)
      while !plates.isIdle, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(16))
      }
      return snapshot()
    }

    private static func png(_ image: CGImage) throws -> Data {
      let out = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          out, UTType.png.identifier as CFString, 1, nil)
      else { throw CocoaError(.fileWriteUnknown) }
      CGImageDestinationAddImage(destination, image, nil)
      guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
      return out as Data
    }

    private static func lights(in entity: Entity, root: Entity, into out: inout [[String: Any]]) {
      guard entity.isEnabled else { return }
      let world = entity.transformMatrix(relativeTo: root)
      let position = [world.columns.3.x, world.columns.3.y, world.columns.3.z]
      // RealityKit lights shine down their entity's -z.
      let forward = -simd_normalize(SIMD3(world.columns.2.x, world.columns.2.y, world.columns.2.z))
      let base: [String: Any] = [
        "name": entity.name, "position": position, "direction": [forward.x, forward.y, forward.z],
      ]
      if let point = entity.components[PointLightComponent.self], point.intensity > 0 {
        out.append(
          base.merging([
            "type": "point", "colour": point.color.hex, "intensity": point.intensity,
            "radius": point.attenuationRadius,
          ]) { $1 })
      }
      if let spot = entity.components[SpotLightComponent.self], spot.intensity > 0 {
        out.append(
          base.merging([
            "type": "spot", "colour": spot.color.hex, "intensity": spot.intensity,
            "radius": spot.attenuationRadius, "inner": spot.innerAngleInDegrees,
            "outer": spot.outerAngleInDegrees,
            "shadow": entity.components.has(SpotLightComponent.Shadow.self),
          ]) { $1 })
      }
      if let sun = entity.components[DirectionalLightComponent.self], sun.intensity > 0 {
        out.append(
          base.merging([
            "type": "directional", "colour": sun.color.hex, "intensity": sun.intensity,
            "shadow": entity.components.has(DirectionalLightComponent.Shadow.self),
          ]) { $1 })
      }
      for child in entity.children { lights(in: child, root: root, into: &out) }
    }
  }

  /// A minimal glTF 2.0 binary writer: positions, normals, texture coordinates and triangles, with
  /// each material's colour, roughness, metalness, emission, opacity and base colour texture (as PNG).
  @MainActor
  private struct GLBWriter {
    private var buffer = Data()
    private var views: [[String: Any]] = []
    private var accessors: [[String: Any]] = []
    private var meshes: [[String: Any]] = []
    private var materials: [[String: Any]] = []
    private var nodes: [[String: Any]] = []
    private var pieces: [Int] = []
    private var textures: [[String: Any]] = []
    private var images: [[String: Any]] = []
    private var textureOf: [ObjectIdentifier: Int] = [:]
    private let device = MTLCreateSystemDefaultDevice()

    mutating func addPiece(_ piece: Entity, relativeTo root: Entity) {
      var children: [Int] = []
      collect(piece, root: root, into: &children)
      guard !children.isEmpty else { return }
      nodes.append(["name": piece.name.isEmpty ? "piece" : piece.name, "children": children])
      pieces.append(nodes.count - 1)
    }

    private mutating func collect(_ entity: Entity, root: Entity, into out: inout [Int]) {
      guard entity.isEnabled else { return }
      if let model = entity.components[ModelComponent.self] {
        let world = entity.transformMatrix(relativeTo: root)
        if let mesh = addMesh(model) {
          let m = world
          let matrix = [m.columns.0, m.columns.1, m.columns.2, m.columns.3].flatMap {
            [$0.x, $0.y, $0.z, $0.w]
          }
          nodes.append(["name": entity.name, "mesh": mesh, "matrix": matrix])
          out.append(nodes.count - 1)
        }
      }
      for child in entity.children { collect(child, root: root, into: &out) }
    }

    private mutating func addMesh(_ model: ModelComponent) -> Int? {
      let contents = model.mesh.contents
      let firstMaterial = materials.count
      for material in model.materials {
        var out = Self.material(material)
        if let resource = Self.baseTexture(material), let index = addTexture(resource) {
          var pbr = out["pbrMetallicRoughness"] as? [String: Any] ?? [:]
          pbr["baseColorTexture"] = ["index": index]
          out["pbrMetallicRoughness"] = pbr
          if Self.isTransparent(material) { out["alphaMode"] = "BLEND" }
        }
        materials.append(out)
      }
      var primitives: [[String: Any]] = []
      for instance in contents.instances {
        guard let source = contents.models[instance.model] else { continue }
        let t = instance.transform
        for part in source.parts {
          let positions = part.positions.elements.map { p -> SIMD3<Float> in
            let q = t * SIMD4(p, 1)
            return SIMD3(q.x, q.y, q.z)
          }
          guard !positions.isEmpty, let indices = part.triangleIndices?.elements else { continue }
          var attributes: [String: Int] = [
            "POSITION": addAccessor(positions.flatMap { [$0.x, $0.y, $0.z] }, type: "VEC3", bounds: positions)
          ]
          if let normals = part.normals?.elements {
            let turned = normals.map { n -> SIMD3<Float> in
              let q = t * SIMD4(n, 0)
              return simd_normalize(SIMD3(q.x, q.y, q.z))
            }
            attributes["NORMAL"] = addAccessor(turned.flatMap { [$0.x, $0.y, $0.z] }, type: "VEC3")
          }
          if let uvs = part.textureCoordinates?.elements {
            attributes["TEXCOORD_0"] = addAccessor(uvs.flatMap { [$0.x, 1 - $0.y] }, type: "VEC2")
          }
          var primitive: [String: Any] = [
            "attributes": attributes, "indices": addIndices(indices),
          ]
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

    private static func baseTexture(_ material: any RealityKit.Material) -> TextureResource? {
      if let pbr = material as? PhysicallyBasedMaterial { return pbr.baseColor.texture?.resource }
      if let simple = material as? SimpleMaterial { return simple.color.texture?.resource }
      if let flat = material as? UnlitMaterial { return flat.color.texture?.resource }
      return nil
    }

    private static func isTransparent(_ material: any RealityKit.Material) -> Bool {
      if let pbr = material as? PhysicallyBasedMaterial, case .transparent = pbr.blending { return true }
      if let flat = material as? UnlitMaterial, case .transparent = flat.blending { return true }
      return false
    }

    /// The texture's pixels as a PNG, read back through Metal; nil when no 8-bit format takes it.
    private mutating func addTexture(_ resource: TextureResource) -> Int? {
      let key = ObjectIdentifier(resource)
      if let index = textureOf[key] { return index }
      guard let png = png(resource) else { return nil }
      let view = addView(png, target: nil)
      images.append(["bufferView": view, "mimeType": "image/png"])
      textures.append(["source": images.count - 1])
      textureOf[key] = textures.count - 1
      return textures.count - 1
    }

    private func png(_ resource: TextureResource) -> Data? {
      guard let device else { return nil }
      let (width, height) = (resource.width, resource.height)
      let formats: [(MTLPixelFormat, Bool)] = [
        (.rgba8Unorm_srgb, false), (.bgra8Unorm_srgb, true), (.rgba8Unorm, false), (.bgra8Unorm, true),
      ]
      for (format, swap) in formats {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
          pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { continue }
        do { try resource.copy(to: texture) } catch { continue }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
          &bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        if swap {
          for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { continue }
        let out = NSMutableData()
        guard
          let destination = CGImageDestinationCreateWithData(
            out, UTType.png.identifier as CFString, 1, nil)
        else { continue }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { continue }
        return out as Data
      }
      print("GenzLabExport: no readable format for a \(width)x\(height) texture")
      return nil
    }

    private static func material(_ material: any RealityKit.Material) -> [String: Any] {
      var colour = NSColor.white
      var roughness: Float = 0.8
      var metallic: Float = 0
      var emissive = NSColor.black
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
      let c = colour.linear
      let e = emissive.linear
      var out: [String: Any] = [
        "name": kind,
        "pbrMetallicRoughness": [
          "baseColorFactor": [c[0], c[1], c[2], c[3] * opacity], "roughnessFactor": roughness,
          "metallicFactor": metallic,
        ],
        "extras": ["kind": kind, "emissiveIntensity": emission],
      ]
      if emission > 0, e.prefix(3).contains(where: { $0 > 0 }) {
        out["emissiveFactor"] = [e[0], e[1], e[2]]
        out["extensions"] = ["KHR_materials_emissive_strength": ["emissiveStrength": emission]]
      }
      if c[3] * opacity < 0.999 { out["alphaMode"] = "BLEND" }
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

    private mutating func addAccessor(
      _ floats: [Float], type: String, bounds: [SIMD3<Float>]? = nil
    ) -> Int {
      let width = type == "VEC3" ? 3 : 2
      let view = addView(floats.withUnsafeBufferPointer { Data(buffer: $0) }, target: 34962)
      var accessor: [String: Any] = [
        "bufferView": view, "componentType": 5126, "count": floats.count / width, "type": type,
      ]
      if let bounds {
        let low = bounds.reduce(SIMD3(repeating: Float.infinity)) { simd_min($0, $1) }
        let high = bounds.reduce(SIMD3(repeating: -Float.infinity)) { simd_max($0, $1) }
        accessor["min"] = [low.x, low.y, low.z]
        accessor["max"] = [high.x, high.y, high.z]
      }
      accessors.append(accessor)
      return accessors.count - 1
    }

    private mutating func addIndices(_ indices: [UInt32]) -> Int {
      let view = addView(indices.withUnsafeBufferPointer { Data(buffer: $0) }, target: 34963)
      accessors.append([
        "bufferView": view, "componentType": 5125, "count": indices.count, "type": "SCALAR",
      ])
      return accessors.count - 1
    }

    func data() throws -> Data {
      var padded = buffer
      while padded.count % 4 != 0 { padded.append(0) }
      let json: [String: Any] = [
        "asset": ["version": "2.0", "generator": "billet GenzLabExport"],
        "extensionsUsed": ["KHR_materials_emissive_strength", "KHR_materials_unlit"],
        "scene": 0,
        "scenes": [["nodes": pieces]],
        "nodes": nodes, "meshes": meshes, "materials": materials, "accessors": accessors,
        "bufferViews": views, "buffers": [["byteLength": padded.count]],
        "textures": textures, "images": images,
        "samplers": [[String: Any]](),
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

  extension NSColor {
    /// sRGB components as linear light, with alpha.
    fileprivate var linear: [Float] {
      let c = usingColorSpace(.sRGB) ?? .white
      func lin(_ v: CGFloat) -> Float {
        let x = Float(v)
        return x <= 0.04045 ? x / 12.92 : powf((x + 0.055) / 1.055, 2.4)
      }
      return [lin(c.redComponent), lin(c.greenComponent), lin(c.blueComponent), Float(c.alphaComponent)]
    }

    fileprivate var hex: String {
      let c = usingColorSpace(.sRGB) ?? .white
      let v = [c.redComponent, c.greenComponent, c.blueComponent].map {
        Int((max(0, min(1, $0)) * 255).rounded())
      }
      return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
  }

  extension GenzColour {
    fileprivate var hex: String {
      String(
        format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()),
        Int((blue * 255).rounded()))
    }
  }

  extension SIMD3 where Scalar == Float {
    fileprivate var array: [Float] { [x, y, z] }
  }
#endif
