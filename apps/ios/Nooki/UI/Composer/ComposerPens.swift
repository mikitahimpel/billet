import SwiftUI
import Design

/// Picks an ink for the note: an owned one is chosen; a locked one is bought, with the purchase moment's Undo, or
/// opens the Store when the coins are short, closing the sheet since the Store cannot show over it.
@MainActor
func choose(_ ink: PaletteInk, state: HomeState, select: (PaletteInk) -> Void, closeForStore: () -> Void) {
    if ink.isOwned(state.shop.owned) || state.shop.buy(ink) {
        select(ink)
    } else if state.shop.coinsAsk != nil {
        closeForStore()
    }
}

struct Pen: View {
    let ink: PaletteInk
    let owned: Bool
    let selected: Bool
    var length: CGFloat = 54

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Peak()
                        .fill(Color(hex: ink.light))
                        .frame(width: 14, height: 11)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hex: ink.light))
                        .frame(width: 14, height: length - 11)
                        .overlay(alignment: .top) {
                            Rectangle().fill(.white.opacity(0.35)).frame(width: 14, height: 3).padding(.top, 5)
                        }
                }
                .opacity(owned ? 1 : 0.55)
            }
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
            if !owned {
                HStack(spacing: 2) {
                    CoinIcon(size: 8)
                    Text("\(ink.price)").font(.ourioMicro.monospacedDigit())
                }
                .foregroundStyle(Ink.text)
                .padding(.horizontal, Space.xs)
                .background(.thinMaterial, in: .capsule)
            }
        }
        .offset(y: selected ? -8 : 0)
        .animation(.snappy(duration: 0.18), value: selected)
    }
}


private struct PenButton: View {
    let ink: PaletteInk
    let state: HomeState
    let selected: Bool
    var length: CGFloat = 54
    let tap: (PaletteInk) -> Void

    var body: some View {
        let owned = ink.isOwned(state.shop.owned)
        Button { tap(ink) } label: {
            Pen(ink: ink, owned: owned, selected: selected, length: owned ? length : length - 14)
                .frame(minWidth: 30, minHeight: Size.control, alignment: .bottom)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(owned ? "\(ink.name) ink" : "Buy \(ink.name) ink, \(ink.price) coins")
        .accessibilityHint(owned ? "" : "Buys it, or opens the Store when the coins are short")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("ink-\(ink.id)")
    }
}

struct PenHolder: View {
    let style: ComposerStyle
    let state: HomeState
    @Binding var selection: PaletteInk
    let closeForStore: () -> Void

    @State private var cupOpen = false

    var body: some View {
        switch style {
        case .sticky, .desk: strip
        case .papers: cup
        }
    }

    private func pens(length: CGFloat = 54) -> some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            ForEach(state.shop.inks) { ink in
                PenButton(ink: ink, state: state, selected: selection == ink, length: length) { picked in
                    choose(picked, state: state, select: { selection = $0; cupOpen = false }, closeForStore: closeForStore)
                }
            }
        }
        .padding(.horizontal, Space.l)
    }

    private var strip: some View {
        ScrollView(.horizontal) { pens(length: 40).frame(height: 56, alignment: .bottom) }
            .scrollIndicators(.hidden)
    }

    private var cup: some View {
        HStack(alignment: .bottom, spacing: Space.m) {
            Button { withAnimation(.snappy) { cupOpen.toggle() } } label: {
                ZStack(alignment: .bottom) {
                    Pen(ink: selection, owned: true, selected: false, length: 46).offset(y: -18)
                    UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .fill(Ink.surface)
                        .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                            .strokeBorder(Ink.textTertiary.opacity(0.25), lineWidth: 1))
                        .frame(width: 54, height: 36)
                }
                .frame(width: 54, height: 66, alignment: .bottom)
                .clipped()
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Pen cup")
            .accessibilityHint(cupOpen ? "Closes the pens" : "Opens the pens")
            .accessibilityIdentifier("penCup")
            if cupOpen {
                ScrollView(.horizontal) { pens(length: 46).frame(height: 66, alignment: .bottom) }
                    .scrollIndicators(.hidden)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l)
        .frame(height: 70)
    }
}
