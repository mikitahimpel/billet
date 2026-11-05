#if os(macOS)
  import Foundation
  import Pet
  import RealityKit
  import Testing

  @testable import PetSceneReality

  /// Renders the Window Seat's cat where it is sent when told to go to the cardigan on the seat,
  /// for checking by eye. Runs only when `GENZ_CAT_SHOTS` names a folder to write into.
  @MainActor
  @Suite struct GenzCatShots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"] != nil))
    func catSentToTheCardigan() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let layout = GenzLayout.of(.cosyNook)
      let room = GenzRoomCache(suite: "genz-cat-shots-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(120)
      while !(room.isBuilt && room.hasCat), Date.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      try #require(room.hasCat)
      room.setLighting(.amberLantern)
      room.room.isEnabled = true
      let cardigan = try #require(layout.pieces.first { $0.piece.kind == .cardigan })
      let spot = layout.onCatSurface([cardigan.centre.x, cardigan.centre.y])
      room.catHolder.position = room.floorPoint(spot)
      room.catHolder.orientation = simd_quatf(angle: 0.5, axis: [0, 1, 0])

      let renderer = try RealityRenderer()
      renderer.entities.append(room.root)
      let lens = PerspectiveCamera()
      lens.camera.fieldOfViewInDegrees = layout.camera.fieldOfView
      renderer.entities.append(lens)
      renderer.activeCamera = lens
      lens.look(
        at: GenzRoomPoint(3.9, 0.8, 1.5).scene, from: GenzRoomPoint(5.4, 7.6, 4.2).scene,
        relativeTo: nil)
      let image = try await GenzRenderShots.render(renderer, width: 786, height: 1704)
      try GenzRenderShots.write(image, to: folder.appendingPathComponent("cat-to-cardigan.png"))
    }

    /// The first Window Seat, with the cat sent towards the camera, and the daybed's pillows
    /// against the sill.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"] != nil))
    func catSentForwardOnTheFirstSeat() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let layout = GenzLayout.of(.original)
      let room = GenzRoomCache(suite: "genz-cat-shots-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(120)
      while !(room.isBuilt && room.hasCat), Date.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      try #require(room.hasCat)
      room.setLighting(.amberLantern)
      room.room.isEnabled = true
      room.catHolder.position = room.floorPoint(layout.onCatSurface([5.0, 2.2]))
      room.catHolder.orientation = simd_quatf(angle: 0.4, axis: [0, 1, 0])

      let renderer = try RealityRenderer()
      renderer.entities.append(room.root)
      let lens = PerspectiveCamera()
      lens.camera.fieldOfViewInDegrees = layout.camera.fieldOfView
      renderer.entities.append(lens)
      renderer.activeCamera = lens
      lens.look(
        at: GenzRoomPoint(3.4, 1.0, 1.1).scene, from: GenzRoomPoint(6.8, 8.4, 3.0).scene,
        relativeTo: nil)
      let image = try await GenzRenderShots.render(renderer, width: 786, height: 1704)
      try GenzRenderShots.write(image, to: folder.appendingPathComponent("first-seat.png"))
    }

    /// The cat standing, then lifted and leaning, with its shadow as it was (a fixed patch inside
    /// the cat's holder) and as the room now fits it (`fitCatShadow`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"] != nil))
    func theCatsShadow() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_CAT_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let layout = GenzLayout.of(.cosyNook)
      let room = GenzRoomCache(suite: "genz-cat-shadow-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(120)
      while !(room.isBuilt && room.hasCat), Date.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      try #require(room.hasCat)
      room.setLighting(.amberLantern)
      room.room.isEnabled = true
      let shadow = try #require(room.catShadow)
      let ground = room.layout.cat.spot.scene
      let length = layout.cat.length
      let heading: Float = 0.5

      let renderer = try RealityRenderer()
      renderer.entities.append(room.root)
      let lens = PerspectiveCamera()
      lens.camera.fieldOfViewInDegrees = 30
      renderer.entities.append(lens)
      renderer.activeCamera = lens
      lens.look(
        at: ground + [0, length * 0.4, 0],
        from: ground + [length * 2.2, length * 2.4, length * 3.2],
        relativeTo: nil)

      for (name, action, lift, lean) in [
        ("standing", CatAction.idle, Float(0), Float(0)), ("lifted", .dangle, 0.55, 0.13),
      ] {
        room.rig?.play(action, blend: 0)
        room.catHolder.position = ground + [0, length * lift, 0]
        room.catHolder.orientation =
          simd_quatf(angle: heading, axis: [0, 1, 0]) * simd_quatf(angle: lean, axis: [0, 0, 1])
        room.bodyHeading = heading
        for fitted in [false, true] {
          if fitted {
            room.catShadowShape = GenzRoom.catShadowFootprint(
              room.rig?.info[action]?.base ?? .stand)
            room.fitCatShadow(0)
          } else {
            shadow.transform = Transform(
              scale: [0.95, 1, 0.6], rotation: simd_quatf(), translation: [0, 0.015, 0])
          }
          try await Task.sleep(for: .milliseconds(300))
          let image = try await GenzRenderShots.render(renderer, width: 700, height: 700)
          let file = "cat-shadow-\(name)-\(fitted ? "after" : "before").png"
          try GenzRenderShots.write(image, to: folder.appendingPathComponent(file))
        }
      }
    }
  }
#endif
