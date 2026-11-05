import SwiftUI
import UIKit

// The app's shared button and row styles and its navigation bar title style. The tokens they use (type, shape,
// spacing, colours) are in Shared/Kit, where the widgets read them too. The guide is apps/ios/docs/style.md.

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

    /// The app's one card: a warm clay surface lit from above, a light rim along its top and a soft shadow. `warm`
    /// pours honey into the light, for a screen's hero card.
    func nookiCard(radius: CGFloat = Radius.card, warm: Bool = false) -> some View {
        // The shadow is the card's shape's own, not the whole card's: anything changing inside never makes it draw
        // again.
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape
                .fill(LinearGradient(colors: warm ? [CardSurface.warmTop, CardSurface.bottom]
                                                  : [CardSurface.top, CardSurface.bottom],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.02)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    /// A row in a List on `Ink.screen`.
    func nookiRow() -> some View {
        listRowBackground(Ink.surface)
            .listRowSeparatorTint(Ink.separator)
    }
}

private enum CardSurface {
    static let top = Color(light: Color(hex: 0xFFFAF3), dark: Color(hex: 0x4E352A))
    static let warmTop = Color(light: Color(hex: 0xFFEBCB), dark: Color(hex: 0x6E4630))
    static let bottom = Color(light: Color(hex: 0xFBEBD8), dark: Color(hex: 0x3A271F))
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
