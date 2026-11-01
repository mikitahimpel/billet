import CoreGraphics
import SwiftUI

/// The spacing rhythm. A gap off this scale is a bug.
public enum Spacing {
  public static let hair: CGFloat = 4
  public static let small: CGFloat = 8
  public static let medium: CGFloat = 16
  public static let large: CGFloat = 24
  public static let wide: CGFloat = 32
  public static let section: CGFloat = 48
  public static let page: CGFloat = 64
}

/// The one corner scale. Controls are capsules and circles, so they have no radius. Anything
/// nested in a rounded shape is concentric with it: see ``nested(in:padding:)``.
public enum Radius {
  /// A card or scene panel.
  public static let card: CGFloat = 24
  /// Something standing inside a card, on the card's own margin.
  public static let plate = nested(in: card, padding: Spacing.medium)
  /// A sheet of paper.
  public static let paper: CGFloat = 3

  /// The corner that stays concentric with `outer` at `padding` inside it.
  public static func nested(in outer: CGFloat, padding: CGFloat) -> CGFloat {
    max(outer - padding, 0)
  }
}

/// Light and depth. Glows are soft and warm; shadows only ever fall on the dark page.
public enum Glow {
  /// How far a lamp's light spreads around a primary control.
  public static let lamp: CGFloat = 18
  public static let lampOpacity = 0.28
  /// The soft shadow under a panel.
  public static let panelShadow: CGFloat = 16
  public static let panelShadowOpacity = 0.35
  /// The lit hairline along a panel's edge.
  public static let edgeOpacity = 0.14
}

/// The one size and weight of every SF Symbol.
public enum IconStyle {
  public static let font = Font.system(size: 17, weight: .medium)
}

/// Interaction sizes.
public enum Target {
  /// The smallest thing a thumb is asked to hit.
  public static let minimum: CGFloat = 44
  /// One line of a list.
  public static let row: CGFloat = 52
}
