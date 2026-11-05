import SwiftUI

/// The Shop's ink colours for notes and drawings, one card each: the colour, its name and the price pill, or "Yours"
/// once the pair owns it. A buy plays the purchase moment like any other. The Shop opened at an ink (`openShop`)
/// scrolls the shelf to it and rings it in honey.
struct InkShelf: View {
    let state: HomeState
    var highlighted: String? = nil

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                HStack(spacing: Space.m) {
                    ForEach(state.shop.inks) { ink in
                        card(ink).id(ink.id)
                    }
                }
                .padding(.horizontal, Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onChange(of: highlighted, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.spring(duration: 0.45)) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func card(_ ink: PaletteInk) -> some View {
        let owned = ink.isOwned(state.shop.owned)
        return VStack(spacing: Space.s) {
            Circle()
                .fill(ink.color(onDark: false))
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 2))
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
        .frame(width: 116)
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
