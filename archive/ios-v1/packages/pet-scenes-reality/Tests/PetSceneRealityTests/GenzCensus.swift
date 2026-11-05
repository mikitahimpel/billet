#if os(macOS)
  import Foundation
  import Pet
  import RealityKit
  import Testing

  @testable import PetSceneReality

  /// Counts what each styled room draws, piece by piece: models, mesh parts and triangles, and
  /// the lights. Runs only when `GENZ_CENSUS` names a file to write the table into.
  @MainActor
  @Suite struct GenzCensus {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_CENSUS"] != nil))
    func census() async throws {
      var lines: [String] = []
      do {
        for furniture in RoomFurniture.allCases {
          let layout = GenzLayout.of(furniture)
          let room = GenzRoomCache(suite: "genz-census-\(UUID())").room(layout)
          room.startBuilding()
          let deadline = Date.now.addingTimeInterval(120)
          while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
          try #require(room.isBuilt)
          var rows: [(String, Tally)] = []
          for child in room.room.children {
            rows.append((Self.label(child), Tally(child)))
          }
          let total = rows.reduce(Tally()) { $0 + $1.1 }
          lines.append("## \(furniture): \(total)")
          let grouped = Dictionary(grouping: rows, by: \.0).mapValues {
            $0.reduce(Tally()) { $0 + $1.1 }
          }
          for (name, tally) in grouped.sorted(by: { $0.value.triangles > $1.value.triangles }) {
            lines.append("  \(name): \(tally)")
          }
        }
      }
      let url = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_CENSUS"]))
      try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_CENSUS_LIGHTS"] != nil))
    func lightsPerPreset() async throws {
      var lines: [String] = []
      do {
        let layout = GenzLayout.of(.cosyNook)
        let room = GenzRoomCache(suite: "genz-census-\(UUID())").room(layout)
        room.startBuilding()
        let deadline = Date.now.addingTimeInterval(120)
        while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(room.isBuilt)
        room.room.isEnabled = true
        for preset in RoomLighting.allCases {
          room.setLighting(preset)
          var on: [String] = []
          Self.lights(in: room.root, path: "", into: &on)
          lines.append("\(preset): \(on.count) on: \(on.joined(separator: ", "))")
        }
      }
      let url = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_CENSUS_LIGHTS"]))
      try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func lights(in entity: Entity, path: String, into on: inout [String]) {
      guard entity.isEnabled else { return }
      let here = entity.name.isEmpty ? path : entity.name
      if let point = entity.components[PointLightComponent.self], point.intensity > 0 {
        on.append("point@\(here) \(Int(point.intensity))")
      }
      if let spot = entity.components[SpotLightComponent.self], spot.intensity > 0 {
        on.append("spot@\(here) \(Int(spot.intensity))")
      }
      if let sun = entity.components[DirectionalLightComponent.self], sun.intensity > 0 {
        let shadow = entity.components.has(DirectionalLightComponent.Shadow.self) ? "+shadow" : ""
        on.append("dir@\(here) \(Int(sun.intensity))\(shadow)")
      }
      for child in entity.children { lights(in: child, path: here, into: &on) }
    }

    private static func label(_ entity: Entity) -> String {
      if !entity.name.isEmpty { return entity.name }
      if let named = entity.children.first(where: { !$0.name.isEmpty }) { return named.name }
      return "unnamed"
    }
  }

  private struct Tally: CustomStringConvertible {
    var models = 0
    var parts = 0
    var triangles = 0
    var lights = 0

    init() {}

    @MainActor init(_ entity: Entity) {
      if let model = entity.components[ModelComponent.self] {
        models += 1
        for meshModel in model.mesh.contents.models {
          for part in meshModel.parts {
            parts += 1
            triangles += (part.triangleIndices?.count ?? 0) / 3
          }
        }
      }
      if entity.components.has(PointLightComponent.self)
        || entity.components.has(SpotLightComponent.self)
        || entity.components.has(DirectionalLightComponent.self)
      {
        lights += 1
      }
      for child in entity.children { self = self + Tally(child) }
    }

    static func + (a: Tally, b: Tally) -> Tally {
      var t = a
      t.models += b.models
      t.parts += b.parts
      t.triangles += b.triangles
      t.lights += b.lights
      return t
    }

    var description: String {
      "\(triangles) tris, \(parts) parts, \(models) models, \(lights) lights"
    }
  }
#endif
