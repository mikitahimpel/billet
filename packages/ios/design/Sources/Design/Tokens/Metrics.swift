import CoreGraphics

/// Corner radii. Buttons, chips and pills are capsules instead.
public enum Radius {
  public static let tag: CGFloat = 8
  public static let control: CGFloat = 14
  /// Every card, grouped section and list row surface.
  public static let card: CGFloat = 20
  public static let hero: CGFloat = 28
}

/// Spacing scale; `gutter` is the side inset of every screen and sheet, 16 over the room.
public enum Space {
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let gutter: CGFloat = 20
  public static let section: CGFloat = 24
  public static let xl: CGFloat = 32
}

/// Sizes shared by controls.
public enum Size {
  /// A header control: the glass buttons, the avatars and the coin pill. Also the smallest tap target.
  public static let control: CGFloat = 44
  /// A full-width button.
  public static let button: CGFloat = 52
  /// A row in a grouped section.
  public static let row: CGFloat = 54
}
