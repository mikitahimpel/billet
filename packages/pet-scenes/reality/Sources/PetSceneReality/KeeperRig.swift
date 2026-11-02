import CoreGraphics
import Foundation
import OSLog
import Pet
import RealityKit

/// A loaded shopkeeper: its named joints, each kept with its rest transform, and a pose applied on
/// top. Every keeper is made with the same joints (see `scripts/make_shopkeepers.py`), so any of
/// them moves the same way.
@MainActor
final class KeeperRig {
  static let folder = "Shopkeepers"
  static let joints = [
    "body", "head", "eye_L", "eye_R", "ear_L", "ear_R", "arm_L", "arm_R", "tail",
  ]

  let entity: Entity
  private var rest: [String: (entity: Entity, transform: Transform)] = [:]
  private static let log = Logger(subsystem: "com.mikitahimpel.billet", category: "KeeperRig")

  /// `nil` when the model lacks the body or the head, which every pose moves.
  init?(model: Entity) {
    entity = model
    for name in Self.joints {
      guard let joint = model.findEntity(named: name) else { continue }
      rest[name] = (joint, joint.transform)
    }
    guard rest["body"] != nil, rest["head"] != nil else { return nil }
  }

  var head: Entity? { rest["head"]?.entity }

  static func resourceName(_ keeper: Shopkeeper) -> String {
    "Keeper_\(keeper.rawValue)"
  }

  /// The keeper's model from its compiled file, or `nil` when it is missing or will not open.
  static func load(_ keeper: Shopkeeper) async -> Entity? {
    let name = resourceName(keeper)
    guard
      let url = Bundle.module.url(forResource: name, withExtension: "reality", subdirectory: folder)
    else {
      log.error("No file for keeper \(name, privacy: .public)")
      return nil
    }
    do {
      return try await Entity(contentsOf: url)
    } catch {
      log.error("\(name, privacy: .public): \(String(describing: error), privacy: .public)")
      return nil
    }
  }

  func apply(_ pose: KeeperPose) {
    set("body") { transform in
      transform.translation.y += pose.hop
      transform.rotation *= simd_quatf(angle: pose.sway, axis: [0, 0, 1])
      transform.scale *= SIMD3(1, 1 + pose.breath, 1 + pose.breath * 0.5)
    }
    set("head") { transform in
      transform.rotation *=
        simd_quatf(angle: pose.headYaw, axis: [0, 1, 0])
        * simd_quatf(angle: -pose.headPitch, axis: [1, 0, 0])
        * simd_quatf(angle: pose.headTilt, axis: [0, 0, 1])
    }
    // The keeper faces +z, so its left arm is on +x and lifts by turning about +z.
    set("arm_L") { $0.rotation *= simd_quatf(angle: pose.leftArm, axis: [0, 0, 1]) }
    set("arm_R") { $0.rotation *= simd_quatf(angle: -pose.rightArm, axis: [0, 0, 1]) }
    for eye in ["eye_L", "eye_R"] {
      set(eye) { $0.scale.y *= max(1 - 0.9 * pose.blink, 0.05) }
    }
    set("ear_L") { $0.rotation *= simd_quatf(angle: -pose.ear, axis: [1, 0, 0]) }
    set("ear_R") { $0.rotation *= simd_quatf(angle: -pose.ear * 0.4, axis: [1, 0, 0]) }
    set("tail") { $0.rotation *= simd_quatf(angle: pose.tail, axis: [0, 1, 0]) }
  }

  private func set(_ name: String, _ change: (inout Transform) -> Void) {
    guard let (entity, transform) = rest[name] else { return }
    var posed = transform
    change(&posed)
    entity.transform = posed
  }
}

/// The pictures the shop draws for itself.
@MainActor
enum ShopArt {
  /// The street outside the shop window at blue hour: sky, a row of houses with a few lit
  /// windows, a street lamp. Flat shapes in the style bible's night palette.
  static func street(width: Int = 512, height: Int = 336) -> CGImage? {
    guard
      let sky = TabLook.gradient(
        [GenzColour(0x3A5A86), GenzColour(0x162846), GenzColour(0x070C18)], width: width,
        height: height),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let w = CGFloat(width)
    let h = CGFloat(height)
    context.draw(sky, in: CGRect(x: 0, y: 0, width: w, height: h))
    var random = SplitMix(seed: 7)
    // Stars in the top half.
    context.setFillColor(
      GenzColour(0xEEF2F7).cgColor.copy(alpha: 0.7) ?? GenzColour(0xEEF2F7).cgColor)
    for _ in 0..<40 {
      let x = CGFloat(random.unit()) * w
      let y = h * 0.6 + CGFloat(random.unit()) * h * 0.4
      let side = 1 + CGFloat(random.unit()) * 1.5
      context.fill(CGRect(x: x, y: y, width: side, height: side))
    }
    // The far roofs, then the houses across the street.
    context.setFillColor(GenzColour(0x20365A).cgColor)
    var x: CGFloat = -10
    while x < w {
      let roof = h * (0.36 + 0.12 * CGFloat(random.unit()))
      let span = 50 + CGFloat(random.unit()) * 40
      context.fill(CGRect(x: x, y: 0, width: span, height: roof))
      context.move(to: CGPoint(x: x - 4, y: roof))
      context.addLine(to: CGPoint(x: x + span / 2, y: roof + span * 0.3))
      context.addLine(to: CGPoint(x: x + span + 4, y: roof))
      context.fillPath()
      x += span + 6
    }
    x = -20
    var houses: [CGRect] = []
    while x < w {
      let span = 90 + CGFloat(random.unit()) * 60
      let top = h * (0.26 + 0.08 * CGFloat(random.unit()))
      houses.append(CGRect(x: x, y: 0, width: span, height: top))
      context.setFillColor(GenzColour(0x14233D).cgColor)
      context.fill(CGRect(x: x, y: 0, width: span, height: top))
      context.move(to: CGPoint(x: x - 6, y: top))
      context.addLine(to: CGPoint(x: x + span / 2, y: top + span * 0.33))
      context.addLine(to: CGPoint(x: x + span + 6, y: top))
      context.fillPath()
      x += span + 14
    }
    for house in houses {
      for row in 0..<2 {
        for column in 0..<3 where random.unit() < 0.45 {
          let window = CGRect(
            x: house.minX + 14 + CGFloat(column) * (house.width - 28) / 3,
            y: house.height * (0.25 + 0.4 * CGFloat(row)), width: 12, height: 14)
          context.setFillColor(GenzColour(0xFFC36B).cgColor)
          context.fill(window)
          context.setFillColor(GenzColour(0xFFE2B0).cgColor)
          context.fill(window.insetBy(dx: 3, dy: 4))
        }
      }
    }
    // The pavement and a street lamp with its pool of light.
    context.setFillColor(GenzColour(0x0E1A2E).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.08))
    let lamp = w * 0.7
    context.setFillColor(GenzColour(0x0A1220).cgColor)
    context.fill(CGRect(x: lamp - 2, y: 0, width: 4, height: h * 0.42))
    if let glow = CGGradient(
      colorsSpace: space,
      colors: [
        GenzColour(0xFFC36B).cgColor.copy(alpha: 0.9) ?? GenzColour(0xFFC36B).cgColor,
        GenzColour(0xFFC36B).cgColor.copy(alpha: 0) ?? GenzColour(0xFFC36B).cgColor,
      ] as CFArray, locations: [0, 1])
    {
      let bulb = CGPoint(x: lamp, y: h * 0.43)
      context.drawRadialGradient(
        glow, startCenter: bulb, startRadius: 0, endCenter: bulb, endRadius: 40, options: [])
    }
    return context.makeImage()
  }
}
