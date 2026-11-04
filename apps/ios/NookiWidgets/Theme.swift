import SwiftUI
import UIKit

/// Widget colors: the app's honey palette on cream in light mode and on the app's warm brown in dark mode.
enum WidgetInk {
    static let background = Color.dynamic(light: 0xFFF6EC, dark: 0x2A1A12)
    static let card = Color.dynamic(light: 0xF6E8DA, dark: 0x3A281D)
    static let primary = Color.dynamic(light: 0x2B2420, dark: 0xFFF1E4)
    static let secondary = Color.dynamic(light: 0x8A7F76, dark: 0xC9B4A2)
    static let hairline = Color.dynamic(light: 0xEADFD4, dark: 0x4A3427)
    static let accent = Color.honeyDeep

    /// Room backdrop behind Mochi, warm by day and blue-brown at night.
    static func room(night: Bool) -> [Color] {
        night ? [Color(hex: 0x4A3A4E), Color(hex: 0x2B2230)] : [Color(hex: 0xF7E6D4), Color(hex: 0xF0D3B4)]
    }

    static func floor(night: Bool) -> Color { night ? Color(hex: 0x5A4130) : Color(hex: 0xD9B48F) }
}

extension Color {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension Font {
    static func widget(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
