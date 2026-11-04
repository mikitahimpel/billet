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
  /// The pose it ends in, when that is not its base.
  var ends: CatBase?

  var duration: Double { trimEnd - trimStart }
}

/// Where each cat's files are and what its clips are. Every cat lives in `Resources/Cats` as a
/// compiled model, a clip table and one texture per extra coat.
enum CatCatalog {
  static let folder = "Cats"

  /// The resource name of the model's mesh, without extension. A splat cat uses its mesh model's.
  static func resourceName(_ model: CatModel) -> String {
    "Cat_\(model.mesh.rawValue)"
  }

  /// The model's clips by action. Clip names the app does not know are skipped.
  static func clips(_ model: CatModel) -> [CatAction: CatClipRange] {
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
      CatClipInfo(duration: $0.duration, loops: $0.loops, base: $0.base ?? .stand, ends: $0.ends)
    }
  }

  static func defaultBase(_ action: CatAction) -> CatBase {
    switch action {
    case .sleep, .twitch: .sleep
    case .loaf: .loaf
    case .sit, .blink, .look, .tailFlick, .happy, .yawn, .groom, .knead, .slowBlink, .perk,
      .rollOver, .bat, .grab, .wave, .groomFlank, .groomTail, .lickLips, .headTilt, .lookUp:
      .sit
    case .idle, .walk, .crouchWiggle, .pounce, .eat, .stretch, .headbutt, .reachUp, .sniff,
      .dangle, .run, .lieDown, .startle, .carry, .rubSide, .jumpUp, .jumpDown:
      .stand
    }
  }

  // MARK: - Coats

  /// The texture the model wears for `coat`, `Cat_<model>_<coat>.jpg`, or nil for the coat it was
  /// made with, which its own texture already is.
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
}
