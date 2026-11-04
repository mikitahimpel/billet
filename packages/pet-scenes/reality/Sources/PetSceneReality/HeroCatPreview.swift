#if DEBUG
  import CoreGraphics
  import Foundation
  import ImageIO
  import Pet
  import RealityKit

  /// A hand-made cat in progress, shown in place of the room's cat in a debug build so it can be
  /// judged under the app's own look. `BILLET_HERO_CAT` names its USD file (Y up, facing -z,
  /// metres), with `BILLET_HERO_ALBEDO` and `BILLET_HERO_EYE` for its fur and eye textures, and
  /// `BILLET_HERO_EYE_SAT` scaling the iris saturation (default 0.8).
  enum HeroCatPreview {
    static var file: URL? {
      ProcessInfo.processInfo.environment["BILLET_HERO_CAT"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    static func load() async -> Entity? {
      let env = ProcessInfo.processInfo.environment
      guard let file, let albedo = env["BILLET_HERO_ALBEDO"], let eye = env["BILLET_HERO_EYE"]
      else { return nil }
      do {
        let cat = try await Entity(contentsOf: file)
        var fur = PhysicallyBasedMaterial()
        fur.baseColor = .init(
          texture: .init(try await TextureResource(contentsOf: URL(fileURLWithPath: albedo))))
        fur.roughness = 0.9
        fur.metallic = .init(floatLiteral: 0)
        fur.sheen = .init(
          tint: GenzColour(
            env["BILLET_HERO_SHEEN"].flatMap { UInt32($0, radix: 16) } ?? 0x5A3820
          ).platformColour)
        var glass = PhysicallyBasedMaterial()
        let irisSaturation = env["BILLET_HERO_EYE_SAT"].flatMap(Float.init) ?? 0.8
        glass.baseColor = .init(
          texture: .init(
            try await desaturated(URL(fileURLWithPath: eye), saturation: irisSaturation)))
        // Matte, with the highlight painted in: a glossy eye mirrors the room's bright ambient
        // light and greys the pupil.
        glass.roughness = 1.0
        glass.metallic = .init(floatLiteral: 0)
        glass.specular = .init(floatLiteral: 0)
        var whisker = PhysicallyBasedMaterial()
        whisker.baseColor = .init(tint: GenzColour(0xF4EEE2).platformColour)
        whisker.roughness = 0.6
        whisker.metallic = .init(floatLiteral: 0)
        whisker.faceCulling = .none
        SceneParts.visit(cat) { part in
          guard var model = part.components[ModelComponent.self] else { return }
          let names = [part.name, part.parent?.name ?? "", part.parent?.parent?.name ?? ""]
          let isEye = names.contains { $0.contains("Eye") }
          let isWhisker = names.contains { $0.contains("Whisker") }
          model.materials = model.materials.map { _ in isWhisker ? whisker : isEye ? glass : fur }
          part.components.set(model)
        }
        return cat
      } catch {
        return nil
      }
    }

    /// The texture at `url` with its saturation scaled (1 leaves it as painted), mixing each texel
    /// toward its luma in sRGB.
    @MainActor
    private static func desaturated(_ url: URL, saturation: Float) async throws -> TextureResource {
      guard saturation != 1,
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
          bytesPerRow: image.width * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
        let data = context.data
      else { return try await TextureResource(contentsOf: url) }
      context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
      let pixels = data.bindMemory(to: UInt8.self, capacity: image.height * context.bytesPerRow)
      for row in 0..<image.height {
        for column in 0..<image.width {
          let i = row * context.bytesPerRow + column * 4
          let r = Float(pixels[i]), g = Float(pixels[i + 1]), b = Float(pixels[i + 2])
          let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
          for (k, value) in [r, g, b].enumerated() {
            pixels[i + k] = UInt8(min(255, max(0, (luma + (value - luma) * saturation).rounded())))
          }
        }
      }
      guard let out = context.makeImage() else { return try await TextureResource(contentsOf: url) }
      return try await TextureResource(image: out, options: .init(semantic: .color))
    }
  }
#endif
