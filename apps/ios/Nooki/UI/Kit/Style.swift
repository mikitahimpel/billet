import SwiftUI
import UIKit

// The app's type, shape and spacing tokens, and its shared button and row styles; colours are in Ink.swift.
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

extension View {
    /// The one primary action of a screen: honey prominent glass from iOS 26, a honey bordered-prominent capsule
    /// before, its label in heroInk, since white on honey is too faint to read. Give the label
    /// `.frame(maxWidth: .infinity)` for the full-width button.
    @ViewBuilder
    func nookiPrimary() -> some View {
        let styled = font(.nookiHeadline)
            .foregroundStyle(Ink.heroInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.honey)
        if #available(iOS 26, *) {
            styled.buttonStyle(.glassProminent)
        } else {
            styled.buttonStyle(.borderedProminent)
        }
    }

    /// A row in a List on `Ink.screen`.
    func nookiRow() -> some View {
        listRowBackground(Ink.surface)
            .listRowSeparatorTint(Ink.separator)
    }
}

/// SF Rounded navigation titles in `Ink.text`, for every navigation bar in the app. Only the title text changes; the
/// bars keep the system's own backgrounds (glass on iOS 26). Call once at launch.
enum NavigationBarStyle {
    @MainActor
    static func apply() {
        let bar = UINavigationBar.appearance()
        let text = UIColor(Ink.text)
        bar.largeTitleTextAttributes = [.font: rounded(size: 34, weight: .bold, style: .largeTitle), .foregroundColor: text]
        bar.titleTextAttributes = [.font: rounded(size: 17, weight: .semibold, style: .headline), .foregroundColor: text]
    }

    /// SF Rounded at the text style's default size, scaled by Dynamic Type.
    private static func rounded(size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: weight)
        let font = system.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? system
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}
