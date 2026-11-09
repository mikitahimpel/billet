import CoreGraphics

/// The one corner scale. Corners are concentric: a shape nested inside another, inset by `p`, takes the outer
/// radius minus `p`, so the gaps between the two stay even all round.
///
/// - `sheet`: the system sheet, which iOS draws; content at the gutter is concentric with it as a `card`.
/// - `card`: every card, grouped section, tile and panel on a screen or sheet.
/// - `inner`: what sits inside a card's padding: a thumbnail, a peek, a tile in a grid.
/// - `control`: every text field. Half the button height, so a one-line field is the same capsule as the
///   buttons beside it and a taller one keeps their round ends. Buttons, chips and pills are capsules.
public enum Radius {
  public static let card: CGFloat = 24
  public static let sheet: CGFloat = card + Space.gutter
  public static let inner: CGFloat = card - CardMetrics.padding
  public static let control: CGFloat = Size.button / 2
}

/// The padding of every card; `Radius.inner` depends on it.
public enum CardMetrics {
  public static let padding: CGFloat = Space.l
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
  /// The leading icon or art of a card header.
  public static let cardMark: CGFloat = 44
  /// A row in a grouped section.
  public static let row: CGFloat = 54
}
