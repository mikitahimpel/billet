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
