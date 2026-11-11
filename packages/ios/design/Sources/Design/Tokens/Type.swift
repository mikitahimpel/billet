import CoreText
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

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

extension Font {
  // A number that changes keeps its width with tabular digits. Built apart from `monospacedDigit()`,
  // which drops a rounded system font's weight and a custom font's face, so a count came out thin.
  // Computed, so a custom face is scaled for the text size in force when the view draws.
  public static var ourioLargeTitleDigits: Font {
    Look.current.digits(.largeTitle, size: 34, weight: .bold)
  }
  public static var ourioTitleDigits: Font { Look.current.digits(.title2, size: 22, weight: .bold) }
  public static var ourioValueDigits: Font { Look.current.digits(.title3, size: 20, weight: .bold) }
  /// The one count a screen is about: the days together on Us.
  public static var ourioHeroDigits: Font {
    Look.current.digits(.largeTitle, size: 56, weight: .bold)
  }
}

extension Look {
  func digits(_ style: Font.TextStyle, size: CGFloat, weight: Font.Weight) -> Font {
    switch self {
    case .classic:
      // The weight last: `monospacedDigit()` resets it on a rounded face.
      if size == style.defaultSize {
        return .system(style, design: .rounded).monospacedDigit().weight(weight)
      }
      return .system(size: style.scaled(size), design: .rounded).monospacedDigit().weight(weight)
    case .dusk:
      return DisplayFace.digits(size: style.scaled(size), weight: weight, relativeTo: style)
    }
  }
}

extension Font.TextStyle {
  /// The style's point size at the default text size.
  fileprivate var defaultSize: CGFloat {
    switch self {
    case .largeTitle: 34
    case .title2: 22
    case .title3: 20
    case .headline: 17
    default: 0
    }
  }

  /// `size` scaled as this style is at the current text size.
  fileprivate func scaled(_ size: CGFloat) -> CGFloat {
    #if canImport(UIKit)
      UIFontMetrics(forTextStyle: uiKit).scaledValue(for: size)
    #else
      size
    #endif
  }

  #if canImport(UIKit)
    private var uiKit: UIFont.TextStyle {
      switch self {
      case .largeTitle: .largeTitle
      case .title2: .title2
      case .title3: .title3
      case .headline: .headline
      default: .body
      }
    }
  #endif
}

extension DisplayFace {
  /// The face with tabular figures, asked of the font itself, since `Font.monospacedDigit()` loses a
  /// custom face.
  static func digits(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) -> Font {
    #if canImport(UIKit)
      let descriptor = UIFontDescriptor(fontAttributes: [
        .name: name(weight),
        .featureSettings: [
          [
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
          ]
        ],
      ])
      return Font(UIFont(descriptor: descriptor, size: size))
    #else
      return .custom(name(weight), size: size, relativeTo: style).monospacedDigit()
    #endif
  }
}
