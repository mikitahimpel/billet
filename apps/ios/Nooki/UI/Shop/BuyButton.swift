import SwiftUI
import Design

/// The buy on every offer: a tap buys right away and the purchase moment plays, with Undo for a few seconds. Short of
/// coins it shakes and opens the Coins sheet; once everything is owned it reads "Owned" with a separate Place button that takes the
/// couple to the room.
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
            Design.PriceButton(quote.price, was: quote.sum > quote.price ? quote.sum : nil) {
                // Short of coins, the buy opens the Coins sheet at what's missing.
                if state.shop.coins < quote.price { shakes += 1 }
                _ = buy()
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Buy \(name), \(quote.price) coins")
            .accessibilityHint(state.shop.coins >= quote.price ? "Buys it now; you can undo for a few seconds"
                                                          : "Needs \(quote.price - state.shop.coins) more coins; opens Coins")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { _ = buy() }
            .frame(maxWidth: fills ? .infinity : nil, minHeight: fills ? Size.button : nil, alignment: .leading)
        } else {
            HStack(spacing: Space.s) {
                Chip("Owned", symbol: "checkmark")
                SecondaryButton("Place", symbol: "mappin", fullWidth: false) {
                    state.tab = .world
                }
                .fixedSize()
                .accessibilityLabel("Place \(name)")
                .accessibilityHint("Opens the room")
            }
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        }
    }
}
