import FeatureShop
import MomentsInterface
import ShopInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface
import Wire

extension View {
    /// The note's stamp and seal, if the sender chose any, on a face `width` points wide.
    func postage(of note: Note, width: CGFloat) -> some View {
        postage(stamp: note.stamp?.art, seal: note.seal?.art, width: width,
                postmark: note.unsent == true ? nil : note.date)
    }
}

/// Stamp and seal are each optional. Each is unlocked once for the pair: a locked one shows its price, and a tap asks
/// before it buys. Short of coins the composer closes for the Coins sheet, which cannot show over it. Until the
/// pair's room has answered nothing counts as unlocked, so a note never goes out with one the server would refuse.
struct PostagePicker: View {
    @Binding var stamp: NoteStamp?
    @Binding var seal: NoteSeal?
    let state: HomeState
    let closeForStore: () -> Void

    @State private var open = false
    @State private var phase = PostageUnlockMachine.State.idle

    var body: some View {
        Button { open = true } label: {
            Group {
                if let stamp {
                    PostageStamp(stamp.art, width: 22)
                } else if let seal {
                    WaxSeal(seal.art, size: 26)
                } else {
                    Image(systemName: "envelope")
                        .font(.ourioCallout.weight(.semibold))
                        .foregroundStyle(Ink.text)
                }
            }
            .frame(width: Size.control, height: Size.control)
            .background(Ink.surface, in: .circle)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Stamp and seal")
        .accessibilityValue(summary)
        .accessibilityIdentifier("composerPostage")
        .popover(isPresented: $open) {
            PostageTray(stamp: $stamp, seal: $seal, owned: state.shop.owned) { postage, owned in
                send(.tapped(postage, owned: owned))
            }
            .sheet(item: confirming) { postage in
                PostageUnlockSheet(postage: postage, shop: state.shop) { send(.buyTapped) }
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private var summary: String {
        [stamp.map { "\($0.art.name) stamp" }, seal.map { "\($0.art.name) seal" }]
            .compactMap(\.self).joined(separator: ", ").nonEmpty ?? "None"
    }

    /// The confirm sheet is up while the machine confirms; closing it cancels.
    private var confirming: Binding<NotePostage?> {
        Binding {
            if case .confirming(let postage) = phase { postage } else { nil }
        } set: { postage in
            if postage == nil { send(.cancelled) }
        }
    }

    private func send(_ event: PostageUnlockMachine.Event) {
        let (next, outputs) = PostageUnlockMachine.transition(phase, event)
        phase = next
        for output in outputs {
            switch output {
            case .select(let postage):
                switch postage.kind {
                case .stamp(let picked): stamp = picked
                case .seal(let picked): seal = picked
                }
            case .buy(let postage):
                if state.shop.buy(postage) {
                    send(.bought)
                } else if state.shop.coinsAsk != nil {
                    send(.coinsShort)
                } else {
                    send(.refused)
                }
            case .openCoins:
                open = false
                closeForStore()
            }
        }
    }
}

/// The popover's stamps and seals, each a 44-point button over its price while locked. Its text stops growing at the
/// largest regular size: at the accessibility sizes the prices would run into each other under the buttons.
struct PostageTray: View {
    @Binding var stamp: NoteStamp?
    @Binding var seal: NoteSeal?
    let owned: Set<String>
    let tapped: (NotePostage, _ owned: Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Size.control), spacing: Space.s, alignment: .top),
              count: typeSize.isAccessibilitySize ? 3 : 6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Stamp")
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s) {
                none(selected: stamp == nil) { stamp = nil }
                ForEach(NoteStamp.allCases, id: \.self) { option in
                    choice(NotePostage(option), selected: stamp == option) {
                        PostageStamp(option.art, width: 26)
                    }
                }
            }
            SectionHeader("Seal")
            LazyVGrid(columns: columns, alignment: .leading, spacing: Space.s) {
                none(selected: seal == nil) { seal = nil }
                ForEach(NoteSeal.allCases, id: \.self) { option in
                    choice(NotePostage(option), selected: seal == option) {
                        WaxSeal(option.art, size: 32)
                    }
                }
            }
        }
        .padding(Space.l)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("postageTray")
        .haptic(.selection, trigger: stamp)
        .haptic(.selection, trigger: seal)
    }

    private func none(selected: Bool, action: @escaping () -> Void) -> some View {
        button("None", selected: selected, action: action) {
            Image(systemName: "circle.slash")
                .font(.ourioCallout)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func choice<Label: View>(
        _ postage: NotePostage, selected: Bool, @ViewBuilder label: () -> Label
    ) -> some View {
        let owned = postage.isOwned(self.owned)
        return VStack(spacing: Space.xs) {
            button(owned ? postage.name : "Unlock \(postage.name), \(postage.price) coins", selected: selected) {
                tapped(postage, owned)
            } label: {
                label().opacity(owned ? 1 : 0.55)
            }
            .accessibilityHint(owned ? "" : "Asks before it unlocks it for both of you")
            .accessibilityIdentifier("postage-\(postage.id)")
            if !owned {
                HStack(spacing: Space.xxs) {
                    CoinIcon(size: 12)
                    Text("\(postage.price)").font(.ourioMicro.monospacedDigit())
                }
                .foregroundStyle(Ink.text)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
            }
        }
    }

    private func button<Label: View>(
        _ name: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .frame(width: Size.control, height: Size.control)
                .background(selected ? Color.honey.opacity(0.22) : .clear, in: .circle)
                .overlay { Circle().strokeBorder(selected ? Color.honey : .clear, lineWidth: 2) }
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
