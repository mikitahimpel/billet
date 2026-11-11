import CoreText
import SwiftUI

extension Font {
  // Text styles, so every size follows Dynamic Type: the look's display face for titles and
  // controls, SF Pro for reading.
  public static let ourioLargeTitle = Look.current.display(.largeTitle, size: 34, weight: .bold)
  public static let ourioTitle = Look.current.display(.title2, size: 22, weight: .bold)
  public static let ourioHeadline = Look.current.display(.headline, size: 17, weight: .semibold)
  public static let ourioBody = Font.body
  public static let ourioCallout = Font.system(.subheadline, weight: .medium)
  public static let ourioCaption = Font.system(.footnote, weight: .medium)
  /// 12 pt, the smallest text in the app.
  public static let ourioMicro = Font.system(.caption, design: .rounded, weight: .semibold)
  /// A number or state that is the point of its card: a count, a streak.
  public static let ourioValue = Look.current.display(.title3, size: 20, weight: .bold)

  /// A hero number on a widget or a stat: fixed, because its frame is.
  public static let ourioNumber = Look.current.display(fixed: 52, weight: .heavy)
}

extension Look {
  /// `size` is the style's size at the default text size, which a custom face scales from.
  func display(_ style: Font.TextStyle, size: CGFloat, weight: Font.Weight) -> Font {
    switch self {
    case .classic: .system(style, design: .rounded, weight: weight)
    case .dusk: .custom(DisplayFace.name(weight), size: size, relativeTo: style)
    }
  }

  func display(fixed size: CGFloat, weight: Font.Weight) -> Font {
    switch self {
    case .classic: .system(size: size, weight: weight, design: .rounded)
    case .dusk: .custom(DisplayFace.name(weight), fixedSize: size)
    }
  }
}

/// Bricolage Grotesque, the landing's display face. The app ships it (`Resources/Fonts`), not this
/// package, so the widgets and the other extensions carry no font; a process without it draws the
/// system face. Registered the first time a name is asked for, which is the first `.ourio*` font.
enum DisplayFace {
  static func name(_ weight: Font.Weight) -> String {
    _ = registered
    switch weight {
    case .heavy, .black: return "BricolageGrotesque-ExtraBold"
    case .bold: return "BricolageGrotesque-Bold"
    default: return "BricolageGrotesque-SemiBold"
    }
  }

  private static let registered: Bool = {
    let names = [
      "BricolageGrotesque-SemiBold", "BricolageGrotesque-Bold", "BricolageGrotesque-ExtraBold",
    ]
    for name in names {
      // Xcode flattens the folder into the bundle; a package or a bundle that keeps it does not.
      guard
        let url = Bundle.main.url(forResource: name, withExtension: "ttf")
          ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
      else { return false }
      // Already registered (another process entry point, a preview host) is not a failure.
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    return true
  }()
}
