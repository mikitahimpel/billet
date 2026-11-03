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
      let layout = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
      let room = GenzRoomCache(suite: "genz-cat-shots-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(60)
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
      let layout = try #require(GenzLayout.of(.windowSeat, furniture: .original))
      let room = GenzRoomCache(suite: "genz-cat-shots-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(60)
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
  }
#endif
