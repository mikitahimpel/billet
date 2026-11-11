import DecorInterface
import Design
import FeatureDecor
import SwiftUI

/// The closet and the chosen piece's controls, over the room while its pieces are arranged. Not a system sheet:
/// the room stays under the player's finger.
struct DecorPanel: View {
    let state: HomeState
    var done: () -> Void

    private var machine: DecorMachine.State { state.decor.state }
    private var selected: String? { machine.selection }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                if let selected {
                    controls(for: selected)
                } else {
                    closet
                }
            }
        }
        
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decorPanel")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Decorate")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Text(hint)
                    .font(.ourioCaption)
                    .foregroundStyle(machine.verdict == .fits ? Ink.textSecondary : Ink.destructive)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Done") { done() }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .accessibilityIdentifier("decorDone")
        }
    }

    private var hint: String {
        switch machine.verdict {
        case .fits:
            selected == nil ? "Tap a piece, or place one below." : "Drag to move. Tap the floor for your closet."
        case .blocksWay: "That would block \(state.petName)'s way."
        case .occupied: "Something is already there."
        case .outsideRoom: "That's outside the room."
        case .wrongSurface: "It doesn't go there."
        }
    }

    private func controls(for id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Catalog.item(id)?.name ?? id)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            HStack(spacing: Space.s) {
                if machine.canTurn {
                    PillButton("Rotate", symbol: "rotate.right") { state.decor.send(.turned) }
                        .accessibilityIdentifier("decorRotate")
                }
                PillButton("Store", symbol: "tray.and.arrow.down") { state.decor.send(.stored) }
                    .accessibilityIdentifier("decorStore")
            }
            .fixedSize()
        }
    }

    @ViewBuilder private var closet: some View {
        let items = machine.book.closet
        if items.isEmpty {
            Text("Everything you own is in the room. Buy more in the Shop.")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    ForEach(items) { item in
                        let name = Catalog.item(item.id)?.name ?? item.id
                        Button { state.decor.send(.closetTapped(item.id)) } label: {
                            VStack(spacing: Space.xs) {
                                art(item.id)
                                    .frame(width: Size.cardMark + Space.l, height: Size.cardMark + Space.l)
                                    .corners(.inner)
                                Text(name)
                                    .font(.ourioCaption)
                                    .foregroundStyle(Ink.text)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 84)
                            .contentShape(.rect)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel("Place \(name)")
                        .accessibilityHint("Stands it in the room")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func art(_ id: String) -> some View {
        Ink.surfaceRaised.overlay {
            if let image = Thumbnails.image("Item_\(id)", maxPixels: 256) {
                Image(uiImage: image).resizable().scaledToFit().padding(Space.xs)
            }
        }
    }
}
