import SwiftUI

/// The house from outside, with two lit windows, small enough for a Live Activity corner.
public enum TinyHouseArt {
  public static let size = CGSize(width: 80, height: 62)

  public static var art: SceneArt {
    SceneArt(
      size: size,
      marks: [
        Draw.solid(Draw.rect(46, 2, 5, 10), Palette.clayLit),
        Draw.solid(Draw.rect(55, 2, 5, 10), Palette.clayLit),
        Draw.solid(Draw.rect(10, 22, 58, 40), Palette.clay),
        Draw.solid(Draw.rect(18, 30, 17, 15), Palette.light),
        Draw.solid(Draw.rect(43, 30, 17, 15), Palette.light),
        Draw.solid(Draw.shape("M0 24 L39 0 L78 24 V30 L39 6 L0 30 Z"), Palette.clayLit),
      ]
    )
  }
}

/// The heavy house silhouette for the lock screen. It takes the system's tint.
public struct LockHouseGlyph: Shape {
  public init() {}

  public func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 56
    return ScenePath.parse(
      """
      M4 28 L28 6 L36 13.3 V5 H40 V9 H42 V5 H46 V22.5 L52 28 H47 V50 H9 V28 Z
      M15 31 H25 V41 H15 Z M31 31 H41 V41 H31 Z
      """
    )
    .applying(CGAffineTransform(scaleX: scale, y: scale))
  }

  public nonisolated var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
}
