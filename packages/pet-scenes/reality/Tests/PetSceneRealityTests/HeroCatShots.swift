#if os(macOS)
  import Foundation
  import Pet
  import RealityKit
  import Testing

  @testable import PetSceneReality

  /// Review stills of a hand-made cat in the Window Seat as the app builds and lights it, from the
  /// app's own camera, beside Ginger chonk. Runs only when `HERO_SHOTS` names a folder to write into
  /// and `HERO_CAT` a USD file (Y up, facing -z, metres) with `HERO_ALBEDO` and `HERO_EYE` textures.
  @MainActor
  @Suite struct HeroCatShots {
    struct Look {
      var fur: PhysicallyBasedMaterial
      var eye: PhysicallyBasedMaterial
    }

    static func look(albedo: URL, eye: URL) async throws -> Look {
      var fur = PhysicallyBasedMaterial()
      let furTexture = try await TextureResource(contentsOf: albedo)
      fur.baseColor = .init(texture: .init(furTexture))
      fur.roughness = 0.9
      fur.metallic = .init(floatLiteral: 0)
      fur.sheen = .init(tint: GenzColour(UInt32(ProcessInfo.processInfo.environment["HERO_SHEEN"].flatMap { UInt32($0, radix: 16) } ?? 0x5A3820)).platformColour)
      var glass = PhysicallyBasedMaterial()
      glass.baseColor = .init(texture: .init(try await TextureResource(contentsOf: eye)))
      glass.roughness = 0.12
      glass.metallic = .init(floatLiteral: 0)
      glass.clearcoat = .init(floatLiteral: 1)
      glass.clearcoatRoughness = .init(floatLiteral: 0.09)
      glass.specular = .init(floatLiteral: 1)
      return Look(fur: fur, eye: glass)
    }

    static func dress(_ entity: Entity, _ look: Look, receiver: ImageBasedLightReceiverComponent?) {
      SceneParts.visit(entity) { part in
        if let receiver { part.components.set(receiver) }
        guard var model = part.components[ModelComponent.self] else { return }
        let names = [part.name, part.parent?.name ?? "", part.parent?.parent?.name ?? ""]
        let isEye = names.contains { $0.contains("Eye") }
        model.materials = model.materials.map { _ in isEye ? look.eye : look.fur }
        part.components.set(model)
      }
    }

    /// Which way a holder at `spot` turns so its cat (facing -z) looks at `eye`, plus `turn`.
    static func heading(at spot: SIMD3<Float>, facing eye: SIMD3<Float>, turn: Float) -> Float {
      let d = eye - spot
      return atan2(-d.x, -d.z) + turn
    }

    @Test(
      .enabled(
        if: ProcessInfo.processInfo.environment["HERO_SHOTS"] != nil
          && ProcessInfo.processInfo.environment["HERO_CAT"] != nil),
      .timeLimit(.minutes(8)))
    func heroBesideGingerChonk() async throws {
      let env = ProcessInfo.processInfo.environment
      let folder = URL(fileURLWithPath: try #require(env["HERO_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let look = try await Self.look(
        albedo: URL(fileURLWithPath: try #require(env["HERO_ALBEDO"])),
        eye: URL(fileURLWithPath: try #require(env["HERO_EYE"])))
      let layout = GenzLayout.of(.standard)
      let room = GenzRoomCache(suite: "hero-shots-\(UUID())").room(layout)
      room.setCat(CatChoice(model: .gingerChonk))
      room.fit(to: CGSize(width: 430, height: 932))
      room.setLighting(.standard)
      room.startBuilding()
      let deadline = Date.now.addingTimeInterval(120)
      while !(room.isBuilt && room.hasCat), Date.now < deadline {
        try await Task.sleep(for: .milliseconds(20))
      }
      try #require(room.hasCat)
      room.setLighting(.standard)
      room.room.isEnabled = true
      room.rig?.play(.idle, blend: 0)

      // Ginger chonk stays where the room put it; the hero gets a copy of its holder, shadow and all.
      let chonkHolder = room.catHolder
      let heroHolder = chonkHolder.clone(recursive: true)
      let shadowIndex = chonkHolder.children.firstIndex { $0 === room.catShadow }
      for (index, child) in heroHolder.children.enumerated().reversed() where index != shadowIndex {
        child.removeFromParent()
      }
      chonkHolder.parent?.addChild(heroHolder)
      var receiver: ImageBasedLightReceiverComponent?
      SceneParts.visit(chonkHolder) { part in
        if receiver == nil { receiver = part.components[ImageBasedLightReceiverComponent.self] }
      }
      let hero = try await Entity(contentsOf: URL(fileURLWithPath: try #require(env["HERO_CAT"])))
      Self.dress(hero, look, receiver: receiver)
      let scale = layout.cat.length / CatModel.gingerChonk.anatomy.length
      let bounds = hero.visualBounds(relativeTo: nil)
      hero.scale = .one * scale
      hero.position = -[bounds.center.x, bounds.min.y, bounds.center.z] * scale
      heroHolder.addChild(hero)

      let renderer = try RealityRenderer()
      renderer.entities.append(room.root)
      let lens = PerspectiveCamera()
      let home = layout.camera
      lens.camera.fieldOfViewInDegrees = home.fieldOfView
      lens.camera.near = GenzRoom.nearClip
      lens.camera.far = GenzRoom.farClip
      renderer.entities.append(lens)
      renderer.activeCamera = lens

      func shoot(_ name: String, size: SIMD2<Float>, scale pixels: Float, zoom: Float = 1) async throws {
        var camera = GenzCamera(home: home)
        camera.fit(to: size)
        camera.zoom(by: 1 / zoom)
        lens.look(at: camera.target, from: camera.position, relativeTo: nil)
        let image = try await GenzRenderShots.render(
          renderer, width: Int(size.x * pixels), height: Int(size.y * pixels))
        try GenzRenderShots.write(image, to: folder.appendingPathComponent("\(name).png"))
      }
      /// A closer look than the app's zoom allows: along the home camera's line, `lengths` cat
      /// lengths from `target`.
      func closeUp(_ name: String, target: SIMD3<Float>, lengths: Float, size: SIMD2<Float>) async throws {
        var camera = GenzCamera(home: home)
        camera.fit(to: size)
        let back = simd_normalize(camera.position - camera.target)
        lens.look(at: target, from: target + back * layout.cat.length * lengths, relativeTo: nil)
        let image = try await GenzRenderShots.render(
          renderer, width: Int(size.x * 2), height: Int(size.y * 2))
        try GenzRenderShots.write(image, to: folder.appendingPathComponent("\(name).png"))
      }
      var eyeCamera = GenzCamera(home: home)
      eyeCamera.fit(to: [430, 932])
      let eye = eyeCamera.position

      // Side by side on the seat: the hero where the cat lives, Ginger chonk a length along.
      let spot = chonkHolder.position
      heroHolder.position = spot
      chonkHolder.position = room.floorPoint(room.floorSpot(-1.5708, 1.0))
      heroHolder.orientation = simd_quatf(
        angle: Self.heading(at: heroHolder.position, facing: eye, turn: 0.55), axis: [0, 1, 0])
      chonkHolder.orientation = simd_quatf(
        angle: Self.heading(at: chonkHolder.position, facing: eye, turn: 0.55), axis: [0, 1, 0])
      try await shoot("1-promax-home", size: [430, 932], scale: 2)
      try await shoot("2-se-home", size: [375, 667], scale: 2)
      let lift = SIMD3<Float>(0, layout.cat.length * 0.35, 0)
      try await closeUp(
        "3-pair-close", target: (heroHolder.position + chonkHolder.position) / 2 + lift, lengths: 7,
        size: [430, 932])
      heroHolder.orientation = simd_quatf(
        angle: Self.heading(at: heroHolder.position, facing: eye, turn: -0.5), axis: [0, 1, 0])
      try await closeUp(
        "4-hero-close", target: hero.convert(position: SIMD3<Float>(0, 0.16, 0.0), to: nil), lengths: 3.0,
        size: [430, 932])

      // The face from two headings: the eyes' highlight is the lamp's own, so it stays lamp-side.
      // Points in the model's own metres (Y up, facing -z): the head's centre and the body's.
      let headPoint = SIMD3<Float>(0, 0.235, -0.04)
      let bodyPoint = SIMD3<Float>(0, 0.15, 0.03)
      for (name, turn) in [("5-face-left", Float(-0.55)), ("6-face-right", Float(0.45))] {
        heroHolder.orientation = simd_quatf(
          angle: Self.heading(at: heroHolder.position, facing: eye, turn: turn), axis: [0, 1, 0])
        try await closeUp(
          name, target: hero.convert(position: headPoint, to: nil), lengths: 1.4, size: [430, 600])
      }

      // Turntable in the room: the hero alone at its spot, close, every 10 degrees.
      chonkHolder.isEnabled = false
      let turns = Int(env["HERO_TURN_FRAMES"] ?? "36") ?? 36
      let base = Self.heading(at: heroHolder.position, facing: eye, turn: 0)
      for frame in 0..<turns {
        heroHolder.orientation = simd_quatf(
          angle: base + Float(frame) / Float(turns) * 2 * .pi, axis: [0, 1, 0])
        try await closeUp(
          String(format: "turn-%03d", frame), target: hero.convert(position: bodyPoint, to: nil),
          lengths: 3.0, size: [300, 400])
      }
    }
  }
#endif
