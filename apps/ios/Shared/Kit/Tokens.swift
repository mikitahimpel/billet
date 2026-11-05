import SwiftUI
import UIKit

// The app's type, shape and spacing tokens, shared with the widgets; colours are in Ink.swift beside it.
// The guide that explains them is apps/ios/docs/style.md.

extension Color {
    /// A colour that follows the system appearance.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

extension Font {
    // Text styles, so every size follows Dynamic Type: SF Rounded for display and controls, SF Pro for reading.
    static let nookiLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let nookiTitle = Font.system(.title2, design: .rounded, weight: .bold)
    static let nookiHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let nookiBody = Font.body
    static let nookiCallout = Font.system(.subheadline, weight: .medium)
    static let nookiCaption = Font.system(.footnote, weight: .medium)
    static let nookiMicro = Font.system(.caption2, design: .rounded, weight: .semibold)
}

/// Corner radii. Buttons, chips and pills are capsules instead.
enum Radius {
    static let tag: CGFloat = 8
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let hero: CGFloat = 28
}

/// Spacing scale; `gutter` is the side margin of screens and sheets, 16 over the room.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let gutter: CGFloat = 20
    static let section: CGFloat = 24
    static let xl: CGFloat = 32
}
