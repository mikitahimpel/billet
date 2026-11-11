import CoreGraphics

/// Concentric: a shape inset by `p` inside another takes the outer radius minus `p`.
/// `sheet` is drawn by iOS; `control` is for text fields, so they match the capsule buttons.
public enum Radius {
  public static let card: CGFloat = 28
  public static let sheet: CGFloat = card + Space.gutter
  public static let inner: CGFloat = card - CardMetrics.padding
  public static let control: CGFloat = Size.button / 2
}

public enum CardMetrics {
  public static let padding: CGFloat = Space.l
}

public enum Space {
  /// Between a title and the line under it.
  public static let xxs: CGFloat = 2
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let gutter: CGFloat = 20
  public static let section: CGFloat = 24
  public static let xl: CGFloat = 32
}

public enum Size {
  /// Also the smallest tap target.
  public static let control: CGFloat = 44
  public static let button: CGFloat = 52
  public static let cardMark: CGFloat = 44
  /// The badge of an `ActionTile`.
  public static let tileMark: CGFloat = 36
  public static let row: CGFloat = 54
  /// A price tag or pill button: shorter than `control`, which stays its tap area.
  public static let pill: CGFloat = 36
}
