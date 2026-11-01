import SwiftUI

/// What a mark is filled or stroked with. Coordinates are in the art's own units.
public enum ScenePaint: Sendable {
  case solid(Swatch)
  case linear([Swatch], from: CGPoint, to: CGPoint)
  /// A soft pool of light: `swatch` at `opacity` in the middle, nothing at `radius`.
  case glow(Swatch, opacity: Double, center: CGPoint, radius: CGFloat)
}

/// One shape in a scene, painted over everything before it.
public struct SceneMark {
  public enum Style {
    case fill(evenOdd: Bool)
    case stroke(StrokeStyle)
  }

  public let path: Path
  public let paint: ScenePaint
  public let style: Style
  public let opacity: Double
}

/// A drawing: its size and its marks, back to front.
public struct SceneArt {
  public let size: CGSize
  public let marks: [SceneMark]
}

/// The vocabulary the scenes are drawn in.
enum Draw {
  static func solid(_ path: Path, _ paint: ScenePaint, opacity: Double = 1) -> SceneMark {
    SceneMark(path: path, paint: paint, style: .fill(evenOdd: false), opacity: opacity)
  }

  static func solid(_ path: Path, _ swatch: Swatch, opacity: Double = 1) -> SceneMark {
    solid(path, .solid(swatch), opacity: opacity)
  }

  static func rect(
    _ x: CGFloat,
    _ y: CGFloat,
    _ width: CGFloat,
    _ height: CGFloat,
    radius: CGFloat = 0
  ) -> Path {
    Path(
      roundedRect: CGRect(x: x, y: y, width: width, height: height),
      cornerRadius: radius,
      style: .continuous
    )
  }

  static func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
    ellipse(x, y, radius, radius)
  }

  static func ellipse(_ x: CGFloat, _ y: CGFloat, _ radiusX: CGFloat, _ radiusY: CGFloat) -> Path {
    Path(
      ellipseIn: CGRect(x: x - radiusX, y: y - radiusY, width: radiusX * 2, height: radiusY * 2)
    )
  }

  static func shape(_ data: String) -> Path {
    ScenePath.parse(data)
  }

  /// A round-capped line.
  static func line(
    _ data: String,
    _ swatch: Swatch,
    width: CGFloat,
    dash: [CGFloat] = [],
    opacity: Double = 1
  ) -> SceneMark {
    SceneMark(
      path: ScenePath.parse(data),
      paint: .solid(swatch),
      style: .stroke(
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash)
      ),
      opacity: opacity
    )
  }

  /// The one ornament: a four-point sparkle.
  static func sparkle(
    _ x: CGFloat,
    _ y: CGFloat,
    size: CGFloat,
    _ swatch: Swatch,
    opacity: Double = 1
  ) -> SceneMark {
    let path = ScenePath.parse("M0 -1 Q0 0 1 0 Q0 0 0 1 Q0 0 -1 0 Q0 0 0 -1Z")
      .applying(CGAffineTransform(scaleX: size, y: size))
      .applying(CGAffineTransform(translationX: x, y: y))
    return solid(path, swatch, opacity: opacity)
  }

  /// The same marks turned a few degrees about a point, the way a hand places things.
  static func tilted(
    _ degrees: Double,
    aroundX x: CGFloat,
    y: CGFloat,
    _ marks: [SceneMark]
  ) -> [SceneMark] {
    let radians = degrees * .pi / 180
    let turn = CGAffineTransform(translationX: -x, y: -y)
      .concatenating(CGAffineTransform(rotationAngle: radians))
      .concatenating(CGAffineTransform(translationX: x, y: y))
    return marks.map {
      SceneMark(
        path: $0.path.applying(turn),
        paint: $0.paint,
        style: $0.style,
        opacity: $0.opacity
      )
    }
  }
}
