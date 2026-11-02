import CoreGraphics
import Foundation
import ImageIO
import Pet

/// One clip in a cat's timeline: the seconds to trim, and the pose it starts and ends in.
struct CatClipRange: Decodable, Hashable, Sendable {
  var trimStart: Double
  var trimEnd: Double
  var loops: Bool
  var base: CatBase?

  var duration: Double { trimEnd - trimStart }
}

/// Where each cat's files are and what its clips are. Mochi keeps its original files; the others
/// live in `Resources/Cats` as a compiled model, a clip table and, for painted cats, a palette or
/// one texture per extra coat.
enum CatCatalog {
  static let folder = "Cats"

  /// The resource name of the model, without extension.
  static func resourceName(_ model: CatModel) -> String {
    model == .mochi ? NookiAssets.mochiName : "Cat_\(model.rawValue)"
  }

  /// The model's clips by action. Clip names the app does not know are skipped.
  static func clips(_ model: CatModel) -> [CatAction: CatClipRange] {
    if model == .mochi { return mochiClips }
    guard
      let url = Bundle.module.url(
        forResource: "\(resourceName(model)).clips", withExtension: "json", subdirectory: folder),
      let data = try? Data(contentsOf: url),
      let table = try? JSONDecoder().decode([String: CatClipRange].self, from: data)
    else { return [:] }
    return decoded(table)
  }

  static func decoded(_ table: [String: CatClipRange]) -> [CatAction: CatClipRange] {
    var out: [CatAction: CatClipRange] = [:]
    for (name, range) in table {
      guard let action = CatAction(rawValue: name), range.duration > 0 else { continue }
      var range = range
      range.base = range.base ?? defaultBase(action)
      out[action] = range
    }
    return out
  }

  /// What the scheduler needs to know about each clip.
  static func info(_ clips: [CatAction: CatClipRange]) -> [CatAction: CatClipInfo] {
    clips.mapValues {
      CatClipInfo(duration: $0.duration, loops: $0.loops, base: $0.base ?? .stand)
    }
  }

  /// Mochi's table, from the trims the room has always used.
  static let mochiClips: [CatAction: CatClipRange] = Dictionary(
    uniqueKeysWithValues: NookiClip.allCases.compactMap { clip in
      CatAction(rawValue: clip.rawValue).map { action in
        (
          action,
          CatClipRange(
            trimStart: clip.trim.lowerBound, trimEnd: clip.trim.upperBound, loops: clip.loops,
            base: defaultBase(action))
        )
      }
    })

  static func defaultBase(_ action: CatAction) -> CatBase {
    switch action {
    case .sleep, .twitch: .sleep
    case .sit, .blink, .look, .tailFlick, .happy, .yawn, .groom, .knead, .slowBlink, .perk,
      .rollOver, .bat:
      .sit
    case .idle, .walk, .crouchWiggle, .pounce, .eat, .stretch, .headbutt, .reachUp: .stand
    }
  }

  // MARK: - Size

  /// How much each model is scaled beside Mochi, so every cat reads the same size in a room.
  /// The made cats were built to Mochi's size; the found ones are tuned by eye in the room.
  static func fit(_ model: CatModel) -> Float {
    switch model {
    case .mochi, .tabby, .plush, .detailed, .detailedKitten, .detailedFluffy, .chibi, .kitten,
      .tuxedo:
      1
    case .blocky: 0.85
    case .slim: 0.8
    }
  }

  /// Mochi's longest side across the floor, in its own metres. A styled room scales every cat
  /// by its own cat length over this, so cats with long tails are not shrunk.
  static let mochiReach: Float = 0.2998

  // MARK: - Coats

  /// The palette grid every painted cat shares: 4 by 4 swatches, in this order from the top left.
  static let grid = 4
  enum Swatch: Int {
    case base = 0
    case stripe = 1
    case belly = 2
    case light = 7
  }

  /// Colours a coat puts on the four swatches it owns, as 0xRRGGBB.
  static func colours(_ coat: CatCoat, keepsWhiteBelly: Bool) -> [Swatch: UInt32]? {
    let colours: [Swatch: UInt32]? =
      switch coat {
      case .natural: nil
      case .ginger: [.base: 0xEE9446, .stripe: 0xC8612A, .belly: 0xFFE6C7, .light: 0xF7B26A]
      case .greyWhite: [.base: 0x8E9096, .stripe: 0x5E6066, .belly: 0xF7F5F2, .light: 0xABADB2]
      case .black: [.base: 0x2A272C, .stripe: 0x18161A, .belly: 0x3E3A40, .light: 0x3A363D]
      case .cream: [.base: 0xF3DDB5, .stripe: 0xE2BF8C, .belly: 0xFFF6E8, .light: 0xFAE9CC]
      }
    guard var colours else { return nil }
    if keepsWhiteBelly { colours[.belly] = 0xF7F5F2 }
    return colours
  }

  /// The model's palette repainted for `coat`, or nil when the coat is the one it was made with or
  /// the model has no palette. A model painted with a full texture instead ships one texture per
  /// coat, `Cat_<model>_<coat>.jpg`, which is returned as it is.
  static func palette(_ model: CatModel, coat: CatCoat) -> CGImage? {
    if model.paintsCoatTextures { return coatTexture(model, coat: coat) }
    guard
      let colours = colours(coat, keepsWhiteBelly: model == .tuxedo),
      let url = Bundle.module.url(
        forResource: "\(resourceName(model))_palette", withExtension: "png", subdirectory: folder),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return repaint(image, colours)
  }

  static func coatTexture(_ model: CatModel, coat: CatCoat) -> CGImage? {
    guard
      coat != .natural,
      let url = Bundle.module.url(
        forResource: "\(resourceName(model))_\(coat.rawValue)", withExtension: "jpg",
        subdirectory: folder),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  static func repaint(_ image: CGImage, _ colours: [Swatch: UInt32]) -> CGImage? {
    let width = image.width
    let height = image.height
    guard
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let cell = CGSize(width: width / grid, height: height / grid)
    for (swatch, hex) in colours {
      let column = swatch.rawValue % grid
      let row = swatch.rawValue / grid
      context.setFillColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
      // Rows count from the top of the picture; the context's origin is at the bottom.
      context.fill(
        CGRect(
          x: CGFloat(column) * cell.width, y: CGFloat(grid - 1 - row) * cell.height,
          width: cell.width, height: cell.height))
    }
    return context.makeImage()
  }
}
