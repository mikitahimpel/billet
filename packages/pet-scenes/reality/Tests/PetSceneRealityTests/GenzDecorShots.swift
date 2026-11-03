#if os(macOS)
  import Foundation
  import Pet
  import RealityKit
  import Testing

  @testable import PetSceneReality

  /// Renders the Window Seat lit, with the pouf moved through decorating, for checking by eye
  /// what follows a moved piece. Runs only when `GENZ_DECOR_SHOTS` names a folder to write into.
  @MainActor
  @Suite struct GenzDecorShots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_DECOR_SHOTS"] != nil))
    func movedPouf() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_DECOR_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let layout = try #require(GenzLayout.of(.windowSeat, furniture: .cosyNook))
      let room = GenzRoomCache(suite: "genz-decor-shots-\(UUID())").room(layout)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(60)
      while !room.isBuilt, Date.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
      try #require(room.isBuilt)
      room.setLighting(.amberLantern)
      room.room.isEnabled = true

      let index = try #require(layout.pieces.firstIndex { $0.piece.kind == .knitPouf })
      let name = GenzRoom.decorName(layout.pieces[index], index: index)
      let holder = try #require(room.decor.pieces[name]?.holder)
      room.decor.isOn = true
      room.decor.select(holder)
      room.decor.beginDrag(at: [3.0, 3.35])
      room.decor.drag(to: [2.0, 5.0])
      room.decor.endDrag()
      room.decor.isOn = false
      for _ in 0..<180 { room.stepDecor(1.0 / 60) }

      let renderer = try RealityRenderer()
      renderer.entities.append(room.root)
      let lens = PerspectiveCamera()
      lens.camera.fieldOfViewInDegrees = layout.camera.fieldOfView
      renderer.entities.append(lens)
      renderer.activeCamera = lens
      let views: [(String, GenzRoomPoint, GenzRoomPoint)] = [
        ("home", layout.camera.target.room, GenzRoomPoint(12, 16, 10)),
        ("floor", GenzRoomPoint(2.6, 4.2, 0.2), GenzRoomPoint(6.5, 9.5, 3.6)),
      ]
      for (view, target, eye) in views {
        lens.look(at: target.scene, from: eye.scene, relativeTo: nil)
        let image = try await GenzRenderShots.render(renderer, width: 786, height: 1704)
        try GenzRenderShots.write(
          image, to: folder.appendingPathComponent("moved-pouf-\(view).png"))
      }
    }
  }

  extension SIMD3 where Scalar == Float {
    /// This scene point in the room's terms.
    fileprivate var room: GenzRoomPoint { GenzRoomPoint(x, z, y) }
  }
#endif
