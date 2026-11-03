#if os(macOS)
  import CoreGraphics
  import Foundation
  import ImageIO
  import Metal
  import Pet
  import Pet
  import RealityKit
  import Testing
  import UniformTypeIdentifiers

  @testable import PetSceneReality

  /// Renders a styled room's shell and furniture from its home camera and the ends of its orbit,
  /// for checking composition by eye. Runs only when `GENZ_SHOTS` names a folder to write into.
  @MainActor
  @Suite struct GenzRenderShots {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GENZ_SHOTS"] != nil))
    func styledRoomFromEveryAngle() async throws {
      let folder = URL(
        fileURLWithPath: try #require(ProcessInfo.processInfo.environment["GENZ_SHOTS"]))
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let furniture =
        ProcessInfo.processInfo.environment["GENZ_FURNITURE"].flatMap {
          RoomFurniture(rawValue: $0)
        }
        ?? .cosyNook
      let style =
        ProcessInfo.processInfo.environment["GENZ_STYLE"].flatMap { RoomStyle(rawValue: $0) }
        ?? .windowSeat
      let layout = try #require(GenzLayout.of(style, furniture: furniture))
      let home = layout.camera
      let middleYaw = (home.yawLimits.lowerBound + home.yawLimits.upperBound) / 2
      let views: [(String, Float, Float, Float)] = [
        ("home", 0, 0, 1),
        ("left", home.yawLimits.lowerBound - home.yaw, 0, 1),
        ("right", home.yawLimits.upperBound - home.yaw, 0, 1),
        ("low", 0, home.pitchLimits.lowerBound - home.pitch, 1),
        ("high", 0, home.pitchLimits.upperBound - home.pitch, 1),
        ("close", middleYaw - home.yaw, 0, home.zoomLimits.lowerBound),
        ("far", 0, 0, home.zoomLimits.upperBound),
      ]
      let renderer = try RealityRenderer()
      let scene = await Self.scene(layout)
      renderer.entities.append(scene)
      let lens = PerspectiveCamera()
      lens.camera.fieldOfViewInDegrees = home.fieldOfView
      renderer.entities.append(lens)
      renderer.activeCamera = lens
      let size = SIMD2<Float>(393, 852)
      for (name, yaw, pitch, zoom) in views {
        var camera = GenzCamera(home: home)
        camera.fit(to: size)
        camera.drag(yaw: yaw, pitch: pitch)
        camera.zoom(by: 1 / zoom)
        lens.look(at: camera.target, from: camera.position, relativeTo: nil)
        let image = try await Self.render(renderer, width: 786, height: 1704)
        try Self.write(
          image,
          to: folder.appendingPathComponent("\(style.rawValue)-\(furniture.rawValue)-\(name).png"))
      }
      let details: [(String, GenzRoomPoint, GenzRoomPoint)] = [
        ("seat", GenzRoomPoint(3.6, 0.8, 1.4), GenzRoomPoint(4.6, 5.2, 3.2)),
        ("corner", GenzRoomPoint(1.0, 1.8, 1.6), GenzRoomPoint(4.2, 5.4, 2.8)),
        ("wall", GenzRoomPoint(0.3, 3.6, 2.2), GenzRoomPoint(4.6, 4.2, 2.8)),
        ("floor", GenzRoomPoint(4.4, 3.8, 0.3), GenzRoomPoint(5.6, 7.8, 3.2)),
      ]
      for (name, target, eye) in style == .windowSeat ? details : [] {
        lens.look(at: target.scene, from: eye.scene, relativeTo: nil)
        let image = try await Self.render(renderer, width: 1200, height: 900)
        try Self.write(
          image,
          to: folder.appendingPathComponent(
            "\(style.rawValue)-\(furniture.rawValue)-detail-\(name).png"))
      }
    }

    /// The room's shell and pieces placed as the room places them, under a warm lamp, a cool
    /// window light and a soft fill.
    static func scene(_ layout: GenzLayout) async -> Entity {
      let kit = GenzKit()
      await kit.makeTextures()
      let root = Entity()
      for part in layout.shell(kit) { root.addChild(part) }
      for placement in layout.pieces {
        let piece = kit.build(placement.piece)
        let size = placement.piece.kind.size
        piece.position = GenzRoomPoint(-size.x / 2, -size.y / 2, 0).scene
        let holder = Entity()
        holder.position = placement.centre.scene
        holder.orientation = simd_quatf(angle: placement.yaw, axis: [0, 1, 0])
        holder.addChild(piece)
        root.addChild(holder)
      }
      let lamp = Entity()
      lamp.position = layout.lamp.at.scene
      lamp.components.set(
        PointLightComponent(
          color: layout.lampColour.platformColour, intensity: 9000, attenuationRadius: 9))
      root.addChild(lamp)
      let window = Entity()
      window.components.set(
        DirectionalLightComponent(color: GenzColour(0xB8C8F0).platformColour, intensity: 1800))
      window.look(
        at: GenzRoomPoint(4, 3, 1).scene, from: GenzRoomPoint(4.5, -9, 7).scene, relativeTo: nil)
      root.addChild(window)
      let fill = Entity()
      fill.components.set(
        DirectionalLightComponent(color: GenzColour(0xFFE6C8).platformColour, intensity: 900))
      fill.look(
        at: GenzRoomPoint(3, 2, 0).scene, from: GenzRoomPoint(9, 12, 10).scene, relativeTo: nil)
      root.addChild(fill)
      return root
    }

    static func render(_ renderer: RealityRenderer, width: Int, height: Int) async throws
      -> CGImage
    {
      let device = try #require(MTLCreateSystemDefaultDevice())
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm_srgb, width: width, height: height, mipmapped: false)
      descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
      descriptor.storageMode = .shared
      let texture = try #require(device.makeTexture(descriptor: descriptor))
      let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
      // The first frames settle lights and materials.
      for _ in 0..<3 {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
          do {
            try renderer.updateAndRender(
              deltaTime: 1 / 30, cameraOutput: output, onComplete: { _ in done.resume() })
          } catch {
            done.resume(throwing: error)
          }
        }
      }
      var bytes = [UInt8](repeating: 0, count: width * height * 4)
      texture.getBytes(
        &bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0)
      let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
      return try #require(
        CGImage(
          width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    static func write(_ image: CGImage, to url: URL) throws {
      let destination = try #require(
        CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      #expect(CGImageDestinationFinalize(destination))
    }
  }
#endif
