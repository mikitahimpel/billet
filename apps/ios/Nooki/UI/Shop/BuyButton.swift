import SwiftUI
import Design

/// The buy, or "Place" once it is owned: one pill at the price tag's height, so a row of cards ends level
/// whatever each one's state.
struct BuyButton: View {
    let state: HomeState
    /// What the missing pieces cost and what they'd cost one by one; nil once everything is owned.
    let quote: (price: Int, sum: Int)?
    let name: String
    var buy: () -> Bool
    var fills = false

    @State private var shakes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let quote {
            Design.PriceButton(
                quote.price, was: quote.sum > quote.price ? quote.sum : nil,
                label: "Buy \(name), \(quote.price) coins",
                hint: state.shop.coins >= quote.price ? "Buys it now; you can undo for a few seconds"
                    : "Needs \(quote.price - state.shop.coins) more coins; opens Coins"
            ) {
                // Short of coins, the buy opens the Coins sheet at what's missing.
                if state.shop.coins < quote.price { shakes += 1 }
                _ = buy()
            }
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
                // With Reduce Motion the warning is the haptic alone.
                content.offset(x: reduceMotion ? 0 : x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-5, duration: 0.05)
                    LinearKeyframe(5, duration: 0.08)
                    LinearKeyframe(-3, duration: 0.08)
                    SpringKeyframe(0, duration: 0.2)
                }
            }
            .haptic(.warning, trigger: shakes)
            .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        } else {
            PillButton("Place", symbol: "mappin") { state.decorate() }
                .fixedSize()
                .accessibilityLabel("Place \(name)")
                .accessibilityHint("Opens the room")
                .frame(maxWidth: fills ? .infinity : nil, alignment: .leading)
        }
    }
}
