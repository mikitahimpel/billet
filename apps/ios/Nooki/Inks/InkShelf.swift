import SwiftUI

/// The Shop's ink colours for notes and drawings, one card each in a wrapping grid: the colour, its name and the price
/// pill, or "Yours" once the pair owns it. A buy plays the purchase moment like any other. The Shop opened at an ink
/// (`openShop`) scrolls the page to the grid and rings that ink in honey.
struct InkShelf: View {
    let state: HomeState
    var highlighted: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Space.m, alignment: .top)]

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
            // A glossy drop of the ink, lit from the top left like the room's clay.
            Circle()
                .fill(ink.color(onDark: false))
                .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear],
                                                      center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0,
                                                      endRadius: 26)))
                .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            Text(ink.name)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
            if owned {
                Label("Yours", systemImage: "checkmark")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .frame(minHeight: 36)
            } else {
                PriceButton(state: state, quote: (ink.price, ink.price), name: "\(ink.name) ink") {
                    state.shop.buy(ink)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity)
        .shopCard()
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
