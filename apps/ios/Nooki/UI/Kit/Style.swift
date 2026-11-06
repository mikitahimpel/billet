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

    /// The app's one card: a flat solid surface, like a grouped list's cell. `warm` lays a breath of honey over it,
    /// for a screen's hero card.
    func nookiCard(radius: CGFloat = Radius.card, warm: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(Ink.surface)
            if warm { shape.fill(Color.honey.opacity(0.14)) }
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
