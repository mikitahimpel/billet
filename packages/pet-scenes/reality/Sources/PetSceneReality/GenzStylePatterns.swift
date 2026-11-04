import CoreGraphics
import Foundation
import Pet

/// A repeating pattern for a wall, a floor or a curtain, drawn in code into a small square that
/// tiles: whatever crosses one edge comes back in at the opposite one.
enum GenzStylePattern: Hashable {
  case wall(RoomWall)
  case floor(RoomFloor)
  /// A two-colour check, by its base and its stripes' colours.
  case gingham(UInt32, UInt32)

  /// Pixels along each side. Small, as the room is seen from across it.
  static let size = 256

  /// The pattern drawn, or `nil` when it has none or it could not be drawn.
  func image() -> CGImage? {
    let size = Self.size
    guard
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    let canvas = GenzPatternCanvas(context: context, size: CGFloat(size))
    switch self {
    case .wall(let wall):
      let (base, pattern) = wall.colours
      canvas.fill(base)
      guard let pattern else { return nil }
      switch wall {
      case .stripes: canvas.stripes(pattern)
      case .gingham: canvas.gingham(pattern)
      case .dots: canvas.dots(pattern)
      case .trellis: canvas.trellis(pattern)
      case .sprigs: canvas.sprigs(pattern)
      case .night, .rose, .peach, .sage, .oat, .butter, .terracotta, .lavender, .teal, .cocoa:
        return nil
      }
    case .floor(let floor):
      switch floor {
      case .plain: return nil
      case .lightWood, .darkWood: canvas.planks(floor.colour)
      case .herringbone: canvas.herringbone(floor.colour)
      case .tiles: canvas.tiles(floor.colour, grout: 0xD8C8B2)
      }
    case .gingham(let base, let pattern):
      canvas.fill(base)
      canvas.gingham(pattern, bands: 8)
    }
    return context.makeImage()
  }
}

/// Drawing into a pattern's square, with each shape drawn again a side's length away wherever it
/// crosses an edge, so the square tiles.
struct GenzPatternCanvas {
  let context: CGContext
  let size: CGFloat

  func fill(_ hex: UInt32) {
    context.setFillColor(Self.colour(hex))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
  }

  /// Draws `shape` at each offset that can reach the square, so it wraps round the edges.
  func wrapped(_ shape: (CGPoint) -> Void) {
    for x in [-size, 0, size] {
      for y in [-size, 0, size] { shape(CGPoint(x: x, y: y)) }
    }
  }

  /// Wide bands with a thin line between, upright.
  func stripes(_ hex: UInt32) {
    context.setFillColor(Self.colour(hex))
    let period = size / 4
    for index in 0..<4 {
      let x = CGFloat(index) * period
      context.fill(CGRect(x: x, y: 0, width: period * 0.42, height: size))
      context.setFillColor(Self.colour(hex, alpha: 0.55))
      context.fill(CGRect(x: x + period * 0.68, y: 0, width: period * 0.06, height: size))
      context.setFillColor(Self.colour(hex))
    }
  }

  /// See-through bands each way, darker where they cross.
  func gingham(_ hex: UInt32, bands: Int = 6) {
    context.setFillColor(Self.colour(hex, alpha: 0.5))
    let period = size / CGFloat(bands)
    for index in 0..<bands {
      let at = CGFloat(index) * period
      context.fill(CGRect(x: at, y: 0, width: period / 2, height: size))
      context.fill(CGRect(x: 0, y: at, width: size, height: period / 2))
    }
  }

  /// Polka dots, each row shifted half a step.
  func dots(_ hex: UInt32) {
    context.setFillColor(Self.colour(hex))
    let step = size / 4
    let radius = step * 0.17
    for row in 0..<4 {
      for column in 0..<4 {
        let centre = CGPoint(
          x: (CGFloat(column) + (row.isMultiple(of: 2) ? 0.25 : 0.75)) * step,
          y: (CGFloat(row) + 0.5) * step)
        wrapped { offset in
          context.fillEllipse(
            in: CGRect(
              x: centre.x + offset.x - radius, y: centre.y + offset.y - radius,
              width: radius * 2, height: radius * 2))
        }
      }
    }
  }

  /// A diamond lattice of thin lines with a bead where they cross.
  func trellis(_ hex: UInt32) {
    context.setStrokeColor(Self.colour(hex))
    context.setLineWidth(size / 64)
    let period = size / 2
    for step in -4...4 {
      let at = CGFloat(step) * period
      context.move(to: CGPoint(x: at, y: 0))
      context.addLine(to: CGPoint(x: at + size, y: size))
      context.move(to: CGPoint(x: at, y: size))
      context.addLine(to: CGPoint(x: at + size, y: 0))
    }
    context.strokePath()
    context.setFillColor(Self.colour(hex))
    let radius = size / 40
    for row in 0...4 {
      for column in 0...4 where (row + column).isMultiple(of: 2) {
        let centre = CGPoint(x: CGFloat(column) * period / 2, y: CGFloat(row) * period / 2)
        context.fillEllipse(
          in: CGRect(
            x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
      }
    }
  }

  /// Small five-petalled flowers with two leaves, scattered on a half-drop.
  func sprigs(_ hex: UInt32) {
    let step = size / 2
    let petal = size / 34
    for row in 0..<2 {
      for column in 0..<2 {
        let centre = CGPoint(
          x: (CGFloat(column) + (row.isMultiple(of: 2) ? 0.3 : 0.8)) * step,
          y: (CGFloat(row) + 0.5) * step)
        wrapped { offset in
          let at = CGPoint(x: centre.x + offset.x, y: centre.y + offset.y)
          context.setFillColor(Self.colour(0x8EA488))
          for side in [-1.0, 1.0] {
            context.fillEllipse(
              in: CGRect(
                x: at.x + side * petal * 1.4 - petal * 1.1, y: at.y - petal * 3.2,
                width: petal * 2.2, height: petal * 1.1))
          }
          context.setFillColor(Self.colour(hex))
          for index in 0..<5 {
            let angle = Double(index) * 2 * .pi / 5
            let middle = CGPoint(
              x: at.x + cos(angle) * petal * 1.15, y: at.y + sin(angle) * petal * 1.15)
            context.fillEllipse(
              in: CGRect(
                x: middle.x - petal, y: middle.y - petal, width: petal * 2, height: petal * 2))
          }
          context.setFillColor(Self.colour(0xE5C878))
          context.fillEllipse(
            in: CGRect(
              x: at.x - petal * 0.6, y: at.y - petal * 0.6, width: petal * 1.2, height: petal * 1.2)
          )
        }
      }
    }
  }

  /// Rows of boards of a few shades with fine grain, their ends staggered, and dark joints.
  func planks(_ hex: UInt32) {
    let rows = 4
    let height = size / CGFloat(rows)
    for row in 0..<rows {
      let y = CGFloat(row) * height
      let joint = CGFloat((row * 97 + 41) % Int(size))
      for (index, x) in [joint - size, joint].enumerated() {
        let shade = Self.shade(row * 3 + index)
        context.setFillColor(Self.colour(hex, shade: shade))
        context.fill(CGRect(x: x, y: y, width: size, height: height))
        context.fill(CGRect(x: x + size, y: y, width: size, height: height))
      }
      context.setStrokeColor(Self.colour(hex, shade: 0.88, alpha: 0.5))
      context.setLineWidth(1)
      for line in 1..<5 {
        let lineY = y + height * CGFloat(line) / 5 + CGFloat((row + line) % 3) - 1
        context.move(to: CGPoint(x: 0, y: lineY))
        for step in 1...8 {
          let x = size * CGFloat(step) / 8
          context.addLine(
            to: CGPoint(x: x, y: lineY + sin(Double(step + row) * 1.3) * 1.2))
        }
      }
      context.strokePath()
      context.setFillColor(Self.colour(hex, shade: 0.55))
      context.fill(CGRect(x: 0, y: y, width: size, height: 2))
      context.fill(CGRect(x: joint, y: y, width: 2, height: height))
    }
  }

  /// Short boards laid in a stepped zigzag, each a few shades off its neighbours.
  ///
  /// Boards are twice as long as wide; a board lying along and one standing up repeat every
  /// one width across and up, and the whole every four widths along, which an eighth of the
  /// square fits.
  func herringbone(_ hex: UInt32) {
    let width = size / 8
    for shift in -3...3 {
      for step in -10...10 {
        let origin = CGPoint(
          x: CGFloat(step) * width + CGFloat(shift) * 4 * width, y: CGFloat(step) * width)
        let boards = [
          CGRect(x: origin.x, y: origin.y, width: width * 2, height: width),
          CGRect(x: origin.x, y: origin.y + width, width: width, height: width * 2),
        ]
        for board in boards {
          guard board.intersects(CGRect(x: 0, y: 0, width: size, height: size)) else { continue }
          // Seeded by place within the square, so a board leaving one edge matches its return.
          let column = (Int((board.minX / width).rounded()) % 8 + 8) % 8
          let row = (Int((board.minY / width).rounded()) % 8 + 8) % 8
          let seed = column * 7 + row * 3 + Int(board.width)
          let shade = Self.shade(seed)
          context.setFillColor(Self.colour(hex, shade: shade))
          context.fill(board)
          context.setStrokeColor(Self.colour(hex, shade: 0.58))
          context.setLineWidth(1.5)
          context.stroke(board)
        }
      }
    }
  }

  /// Square tiles a little apart in shade, with light grout between.
  func tiles(_ hex: UInt32, grout: UInt32) {
    fill(grout)
    let count = 4
    let side = size / CGFloat(count)
    let gap = size / 96
    for row in 0..<count {
      for column in 0..<count {
        context.setFillColor(Self.colour(hex, shade: Self.shade(row * 5 + column * 3)))
        context.fill(
          CGRect(
            x: CGFloat(column) * side + gap / 2, y: CGFloat(row) * side + gap / 2,
            width: side - gap, height: side - gap))
      }
    }
  }

  /// A shade from 0.9 to 1.08 that looks random but is the same for the same `seed`.
  static func shade(_ seed: Int) -> CGFloat {
    let mixed = (seed &* 2_654_435_761) & 0xFFFF
    return 0.9 + 0.18 * CGFloat(mixed) / 0xFFFF
  }

  static func colour(_ hex: UInt32, shade: CGFloat = 1, alpha: CGFloat = 1) -> CGColor {
    CGColor(
      srgbRed: min(CGFloat((hex >> 16) & 0xFF) / 255 * shade, 1),
      green: min(CGFloat((hex >> 8) & 0xFF) / 255 * shade, 1),
      blue: min(CGFloat(hex & 0xFF) / 255 * shade, 1), alpha: alpha)
  }
}
