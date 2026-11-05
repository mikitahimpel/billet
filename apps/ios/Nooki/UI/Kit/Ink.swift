import SwiftUI

/// The app's colours. The adaptive set (screen to accentText) follows the system appearance and is what screens use;
/// the "on room" set is white on warm glass over the scene in either appearance. Accent fills are `Color.honey` and
/// `.honeyDeep`. The guide is apps/ios/docs/style.md.
enum Ink {
    // MARK: Adaptive surfaces and text

    /// Full screens and sheets: warm cream in light, deep warm brown in dark.
    static let screen = Color(light: Color(hex: 0xFBF3E8), dark: Color(hex: 0x2A1A12))
    /// Cards and list rows on `screen`.
    static let surface = Color(light: .white, dark: Color(hex: 0x3B2C25))
    /// Selected rows, pressed cards, chips on a surface.
    static let surfaceRaised = Color(light: Color(hex: 0xF3E6D6), dark: Color(hex: 0x46352C))
    static let separator = Color(light: Color(hex: 0x3A2114, opacity: 0.12), dark: .white.opacity(0.14))
    /// Titles and body text; 13.6:1 on the cream screen.
    static let text = Color(light: Color(hex: 0x3A2114), dark: .white.opacity(0.96))
    /// Subtitles and captions; 5.7:1 on the cream screen.
    static let textSecondary = Color(light: Color(hex: 0x7A5A45), dark: .white.opacity(0.72))
    /// Placeholders and disabled labels, never body text.
    static let textTertiary = Color(light: Color(hex: 0x3A2114, opacity: 0.45), dark: .white.opacity(0.5))
    /// Honey for text: links, text buttons, checkmarks. Darker on cream to keep 5:1; honey itself in dark.
    static let accentText = Color(light: Color(hex: 0xA4521C), dark: .honey)

    // MARK: On the room, and the dark-only names screens are moving off

    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.72)
    static let hairline = Color.white.opacity(0.14)
    /// Deep warm brown used on top of the light hero card.
    static let heroInk = Color(hex: 0x3A2114)
    static let sheet = Color(hex: 0x2A1A12)
    /// A breath of honey laid into Liquid Glass: light enough that the room still shows through, warm enough that it
    /// never turns grey.
    static let glassTint = Color(hex: 0xF2A65E, opacity: 0.16)
    /// Card fill on the dark sheet.
    static let card = Color.white.opacity(0.08)
}
