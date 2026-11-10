import SwiftUI
import Design

/// The Shop's ink colours for notes and drawings, one card each in a grid of three (two at the accessibility sizes):
/// the colour, its name and the price pill, or "Yours" once the pair owns it. The name keeps one line and the bottom
/// slot one control's height, so every card in a row is the same height. A buy plays the purchase moment like any
/// other. The Shop opened at an ink (`openShop`) scrolls the page to the grid and rings that ink in honey.
struct InkShelf: View {
    let state: HomeState
    var highlighted: String? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top),
              count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            ForEach(state.shop.inks) { ink in
                card(ink).id(ink.id)
            }
        }
        .padding(.horizontal, Space.l)
    }

    private func card(_ ink: PaletteInk) -> some View {
        let owned = ink.isOwned(state.shop.owned)
        return VStack(spacing: Space.s) {
            Circle()
                .fill(ink.color(onDark: false))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                                      center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0,
                                                      endRadius: 26)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text(ink.name)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Group {
                if owned {
                    Chip("Yours", symbol: "checkmark")
                } else {
                    Design.PriceButton(ink.price) { state.shop.buy(ink) }
                }
            }
            .frame(minHeight: Size.control)
        }
        .padding(CardMetrics.padding)
        .frame(maxWidth: .infinity)
        .cardSurface()
        .overlay {
            if highlighted == ink.id {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.honey, lineWidth: 3)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shopInk-\(ink.id)")
    }
}
