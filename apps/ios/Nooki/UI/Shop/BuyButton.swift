import SwiftUI
import Design

/// The buy on every offer: a tap buys right away and the purchase moment plays, with Undo for a few seconds. Short of
/// coins it shakes and opens the Coins sheet; once everything is owned it reads "Owned · Place" and takes the couple
/// to the room.
struct BuyButton: View {
    let state: HomeState
    /// What the missing pieces cost and what they'd cost one by one; nil once everything is owned.
    let quote: (price: Int, sum: Int)?
    /// What the buy is called, for VoiceOver.
    let name: String
    var buy: () -> Bool
    /// Stretches the owned button to the card's width.
    var fills = false

    @State private var shakes = 0

    var body: some View {
        if let quote {
            HStack(spacing: Space.s) {
                Design.PriceButton(
                    quote.price, label: "Buy \(name), \(quote.price) coins",
                    hint: state.shop.coins >= quote.price ? "Buys it now; you can undo for a few seconds"
                        : "Needs \(quote.price - state.shop.coins) more coins; opens Coins"
                ) {
                    // Short of coins, the buy opens the Coins sheet at what's missing.
                    if state.shop.coins < quote.price { shakes += 1 }
                    _ = buy()
                }
                if quote.sum > quote.price {
                    Text(quote.sum, format: .number)
                        .font(.nookiCaption.monospacedDigit())
                        .strikethrough()
                        .foregroundStyle(Ink.textSecondary)
                        .accessibilityHidden(true)
                }
            }
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
            .frame(maxWidth: fills ? .infinity : nil, minHeight: fills ? Size.button : nil, alignment: .leading)
        } else {
            SecondaryButton("Owned · Place", symbol: "checkmark", fullWidth: fills) {
                state.tab = .world
            }
            .accessibilityLabel("\(name), owned")
            .accessibilityHint("Opens the room")
        }
    }
}
