import SwiftUI

/// The top of a Shop sheet: the title with its chips under it, and the close button level with the title.
struct SheetHeader<Chips: View>: View {
    let title: String
    @ViewBuilder let chips: Chips
    var close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title)
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: Space.s) { chips }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.nookiCallout.weight(.bold))
                    .foregroundStyle(Ink.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(Ink.textSecondary)
            .accessibilityLabel("Close")
        }
    }
}

extension View {
    /// A Shop sheet: the system sheet on `Ink.screen` with a detent as tall as its content, and the large detent too
    /// when the content outgrows it (big text sizes); the content scrolls only then.
    /// `tight` turns true, and stays so, when the content is taller than the screen allows (an iPhone SE), so the
    /// sheet can shrink its art instead of scrolling.
    func shopSheet(height: Binding<CGFloat>, tight: Binding<Bool> = .constant(false)) -> some View {
        modifier(ShopSheet(height: height, tight: tight))
    }
}

private struct ShopSheet: ViewModifier {
    @Binding var height: CGFloat
    @Binding var tight: Bool
    /// The home indicator's strip, which the detent's height includes.
    @State private var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottom = $0 }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visible in
            if height > visible + 1, !tight { tight = true }
        }
        .presentationDetents([.height(height + bottom), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ink.screen)
    }
}
