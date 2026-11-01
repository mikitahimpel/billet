import CoreGraphics

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

/// Corner radii, by what they belong to.
public enum Radius {
  /// A scene panel.
  public static let scene: CGFloat = 40
  /// A lit panel.
  public static let panel: CGFloat = 24
  /// A button or tool.
  public static let control: CGFloat = 18
  /// A house number plate.
  public static let plate: CGFloat = 6
  /// A sheet of paper.
  public static let paper: CGFloat = 3
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

/// Interaction sizes.
public enum Target {
  /// The smallest thing a thumb is asked to hit.
  public static let minimum: CGFloat = 44
  /// The primary action.
  public static let primary: CGFloat = 60
}
