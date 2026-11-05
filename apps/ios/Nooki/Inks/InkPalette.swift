import SwiftUI

/// The ink dots for notes and drawings: owned inks pick, a locked one shows its price and a tap buys it, with the
/// purchase moment's Undo. Short of coins it shakes and says how many are missing.
struct InkPalette: View {
    let state: HomeState
    @Binding var selection: PaletteInk
    /// Shows each ink in its dark-paper colour, as the lock-screen canvas draws it.
    var onDark = false
    /// The price under a locked dot.
    var label: Color = Ink.text
    /// Opens the Shop at an ink the coins don't cover yet.
    var openShop: (PaletteInk) -> Void
    var picked: () -> Void = {}

    @State private var short: PaletteInk?
    @State private var shakes = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.inks) { ink in
                dot(ink)
            }
        }
        .haptic(.warning, trigger: shakes)
        .alert(item: $short) { ink in
            Alert(
                title: Text("\(max(0, ink.price - state.coins)) more coins to go"),
                message: Text(
                    "\(ink.name) ink is \(ink.price) coins. Answer today's question or open the daily gift to earn more."),
                primaryButton: .default(Text("Open Shop")) { openShop(ink) },
                secondaryButton: .cancel())
        }
    }

    private func dot(_ ink: PaletteInk) -> some View {
        let owned = ink.isOwned(state.owned)
        let selected = selection == ink
        return Button {
            tap(ink, owned: owned)
        } label: {
            VStack(spacing: 3) {
                Circle()
                    .fill(ink.color(onDark: onDark))
                    .overlay(Circle().strokeBorder(.white.opacity(selected ? 1 : 0.5), lineWidth: selected ? 3 : 1))
                    .overlay {
                        if !owned {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .opacity(owned ? 1 : 0.7)
                if !owned {
                    HStack(spacing: 2) {
                        CoinIcon(size: 9)
                        Text("\(ink.price)")
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .foregroundStyle(label)
                }
            }
            .frame(minWidth: 34, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(owned ? "\(ink.name) ink" : "Buy \(ink.name) ink, \(ink.price) coins")
        .accessibilityHint(owned ? "" : "Buys it now; you can undo for a few seconds")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ink-\(ink.id)")
    }

    private func tap(_ ink: PaletteInk, owned: Bool) {
        if owned {
            selection = ink
            picked()
        } else if state.coins >= ink.price {
            if state.buy(ink) {
                selection = ink
                picked()
            }
        } else {
            shakes += 1
            short = ink
        }
    }
}
