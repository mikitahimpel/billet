import SwiftUI
import Design

/// The ink dots for notes and drawings: owned inks pick, a locked one shows its price and a tap buys it, with the
/// purchase moment's Undo. Short of coins the tap opens the Store, finishing the buy once the coins are there; the
/// note or canvas it sits in closes first, since the Store cannot show over it.
struct InkPalette: View {
    let state: HomeState
    @Binding var selection: PaletteInk
    /// Shows each ink in its dark-paper colour, as the lock-screen canvas draws it.
    var onDark = false
    /// The price under a locked dot.
    var label: Color = Ink.text
    /// Closes the sheet this sits in when the Store opens, for a host that can't show it over itself. The lock-screen
    /// canvas shows the Store over itself.
    var closesForStore = true
    var picked: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.shop.inks) { ink in
                dot(ink)
            }
        }
    }

    private func dot(_ ink: PaletteInk) -> some View {
        let owned = ink.isOwned(state.shop.owned)
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
                                .font(.nookiMicro)
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
                            .font(.nookiMicro.monospacedDigit())
                    }
                    .foregroundStyle(label)
                }
            }
            .frame(minWidth: 34, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(owned ? "\(ink.name) ink" : "Buy \(ink.name) ink, \(ink.price) coins")
        .accessibilityHint(owned ? "" : "Buys it, or opens the Store when the coins are short")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ink-\(ink.id)")
    }

    private func tap(_ ink: PaletteInk, owned: Bool) {
        if owned {
            selection = ink
            picked()
        } else if state.shop.buy(ink) {
            selection = ink
            picked()
        } else if state.shop.coinsAsk != nil, closesForStore {
            dismiss()
        }
    }
}
