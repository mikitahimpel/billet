/// Every colour in billet. Interface colours are few; the ramps below them belong to the art.
public enum Palette {
  // MARK: Interface

  /// The evening sky at the top of every screen, and the top edge of the Home art.
  public static let sky = Swatch(0x0E2E2A)
  /// The ground under the Home art, and its bottom edge.
  public static let meadow = Swatch(0x143B33)
  /// The page every screen stands in: the middle of the standard ground, ember dusk's deep plum
  /// (see ``EveningGround``).
  public static let page = Swatch(0x34172C)
  /// The deepest shade of the page, for shadows on it.
  public static let pageDeep = Swatch(0x1A0A14)
  /// A lamp-lit panel standing on the page.
  public static let raised = Swatch(0x402A1C)
  /// A control standing on a panel.
  public static let raisedTop = Swatch(0x5A3C27)
  /// Primary text, and the paper every note is drawn on.
  public static let paper = Swatch(0xFBF3E6)
  /// Secondary text on warm grounds; the shaded side of paper in the art.
  public static let paperTurned = Swatch(0xE3D2AC)
  /// Quiet text on the page and its rungs.
  public static let muted = Swatch(0xC9BCA6)
  /// The one interface accent: Send, the house number, the focus ring.
  public static let gold = Swatch(0xD9A441)
  /// Text on `gold`, and the darkest ink.
  public static let ink = Swatch(0x2A1208)
  /// The ground behind every house number.
  public static let plate = Swatch(0x1B0B07)

  // MARK: Inks

  /// Gold's stand-in on paper. `gold` itself measures 2.04:1 there.
  public static let inkGold = Swatch(0xB27C20)

  // MARK: Light

  public static let light = Swatch(0xFFD98A)
  public static let lightWarm = Swatch(0xFFE6AE)

  // MARK: Clay

  public static let clayLit = Swatch(0xD06A43)
  public static let clay = Swatch(0xA5442B)
  public static let clayDeep = Swatch(0x6E2F1E)
  public static let clayNight = Swatch(0x53251A)

  // MARK: Green

  public static let greenBright = Swatch(0x57A583)
  public static let greenLit = Swatch(0x3E8A6B)
  public static let green = Swatch(0x2A5C48)
  public static let greenShade = Swatch(0x1C4536)
  public static let greenDeep = Swatch(0x163A2D)
  public static let skyLit = Swatch(0x1F5B44)
  public static let skyNight = Swatch(0x05170F)
  public static let hill = Swatch(0x031009)

  // MARK: Wood

  public static let woodLit = Swatch(0xE0A861)
  public static let wood = Swatch(0x8A5422)
  public static let woodShade = Swatch(0x6B3A17)
  public static let woodDeep = Swatch(0x5A2F0D)
}
