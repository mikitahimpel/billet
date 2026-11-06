import SwiftUI
import Design

/// The price pill on every offer, and the buy itself: a tap buys right away and the purchase moment plays, with Undo
/// for a few seconds. Short of coins it shakes and opens the Coins sheet; once everything is owned it reads
/// "Owned · Place" and takes the couple to the room.
struct PriceButton: View {
    let state: HomeState
    /// What the missing pieces cost and what they'd cost one by one; nil once everything is owned.
    let quote: (price: Int, sum: Int)?
    /// What the buy is called, for VoiceOver.
    let name: String
    var buy: () -> Bool
    /// Stretches the pill to the card's width, as in the grid.
    var fills = false
    /// The owned label's colour: white on the featured art, the text colour on a card.
    var ownedInk: Color = Ink.text

    @State private var shakes = 0

    var body: some View {
        if let quote {
            Button {
                // Short of coins, the buy opens the Coins sheet at what's missing.
                if state.shop.coins < quote.price { shakes += 1 }
                _ = buy()
            } label: {
                CoinPrice(price: quote.price, was: quote.sum)
                    .frame(maxWidth: fills ? .infinity : nil)
            }
            .shopButton()
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-5, duration: 0.05)
                    LinearKeyframe(5, duration: 0.08)
                    LinearKeyframe(-3, duration: 0.08)
                    SpringKeyframe(0, duration: 0.2)
                }
            }
            .haptic(.warning, trigger: shakes)
            .accessibilityLabel("Buy \(name), \(quote.price) coins")
            .accessibilityHint(state.shop.coins >= quote.price ? "Buys it now; you can undo for a few seconds"
                                                          : "Needs \(quote.price - state.shop.coins) more coins; opens Coins")
        } else {
            Button {
                state.tab = .world
            } label: {
                Label("Owned · Place", systemImage: "checkmark")
                    .foregroundStyle(ownedInk)
                    .frame(maxWidth: fills ? .infinity : nil)
            }
            .shopButton(prominent: false)
            .accessibilityLabel("\(name), owned")
            .accessibilityHint("Opens the room")
        }
    }
}
