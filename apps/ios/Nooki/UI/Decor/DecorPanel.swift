import FeatureShop
import DecorInterface
import Design
import FeatureDecor
import SwiftUI
import WidgetUI

/// The closet and the chosen piece's controls, over the room while its pieces are arranged. Not a system sheet:
/// the room stays under the player's finger.
struct DecorPanel: View {
    let state: HomeState
    var done: () -> Void

    private var machine: DecorMachine.State { state.decor.state }
    private var selected: String? { machine.selection }
    @State private var confirmingReset = false

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
        HStack(alignment: .center, spacing: Space.m) {
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
        switch machine.book.notice {
        case .noRoomToTurn: return "There's no room to turn it. Put it away?"
        case .slid: return "It didn't fit there, so it slid to the nearest spot."
        case .swapped: return "Changed places."
        case .rejected: return "That doesn't fit there."
        case .lastRest: return "\(state.petName) needs a bed or a sofa to rest on."
        case .reset: return "The room is as it first was."
        case nil: break
        }
        switch machine.verdict {
        case .fits:
            return selected == nil ? "Tap a piece, or place one below." : "Drag to move. Tap the floor for your closet."
        case .blocksWay: return "That would block \(state.petName)'s way."
        case .occupied: return "Something is already there."
        case .outsideRoom: return "That's outside the room."
        case .wrongSurface: return "It doesn't go there."
        }
    }

    private func controls(for id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Catalog.item(id, cat: state.petName)?.name ?? DecorItem.item(shopID: id)?.base?.title ?? id)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            // One row while the four pills fit, two rows on a narrower phone, one under another at accessibility sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    turnButtons
                    keepButtons
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: Space.s) {
                    HStack(spacing: Space.s) { turnButtons }.fixedSize()
                    HStack(spacing: Space.s) { keepButtons }.fixedSize()
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    turnButtons
                    keepButtons
                }
            }
        }
    }

    @ViewBuilder private var turnButtons: some View {
        if machine.canTurn {
            PillButton("Rotate", symbol: "rotate.right") { state.decor.send(.turned) }
                .accessibilityIdentifier("decorRotate")
            PillButton("45°", symbol: "rotate.right") { state.decor.send(.turnedFine) }
                .accessibilityIdentifier("decorRotateFine")
        }
    }

    @ViewBuilder private var keepButtons: some View {
        PillButton("Store", symbol: "tray.and.arrow.down") { state.decor.send(.stored) }
            .accessibilityIdentifier("decorStore")
        undoButton
    }

    @ViewBuilder private var closet: some View {
        let items = machine.book.closet
        if items.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Everything is in the room. Tap a piece to move, turn or put it away.")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                resetButton
            }
        } else {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(items) { item in
                        let name = Catalog.item(item.id, cat: state.petName)?.name ?? item.base?.title ?? item.id
                        Button { state.decor.send(.closetTapped(item.id)) } label: {
                            VStack(spacing: Space.s) {
                                art(item.id)
                                    .aspectRatio(1, contentMode: .fit)
                                    .corners(.inner)
                                Text(name)
                                    .font(.ourioCallout)
                                    .foregroundStyle(Ink.text)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .containerRelativeFrame(.horizontal, count: 3, spacing: Space.s)
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
            resetButton
        }
    }

    @ViewBuilder private var undoButton: some View {
        if machine.book.undo != nil {
            PillButton("Undo", symbol: "arrow.uturn.backward") { state.decor.send(.undone) }
                .accessibilityIdentifier("decorUndo")
        }
    }

    private var resetButton: some View {
        HStack(spacing: Space.s) {
            PillButton("Reset room", symbol: "arrow.counterclockwise") { confirmingReset = true }
                .accessibilityIdentifier("decorReset")
            Spacer(minLength: 0)
            undoButton
        }
        .confirmationDialog("Put everything back where it first stood? What you bought is placed again where it fits.", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset room", role: .destructive) { state.decor.send(.resetRoom) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func art(_ id: String) -> some View {
        Ink.surfaceRaised.overlay {
            if let image = Thumbnails.image("Item_\(id)", maxPixels: 256) {
                Image(uiImage: image).resizable().scaledToFit().padding(Space.xs)
            } else {
                Image(systemName: Self.symbol(id))
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.textSecondary)
            }
        }
    }

    private static func symbol(_ id: String) -> String {
        switch id {
        case "base-donutbed": "bed.double"
        case "base-cattree": "tree"
        case "base-plant": "leaf"
        case "base-lamp": "lamp.floor"
        case "base-rug": "square.grid.2x2"
        case "base-bowls": "fork.knife"
        case "base-books": "books.vertical"
        case "base-windowseat": "window.vertical.open"
        case "base-nightstand": "tablecells"
        default: "shippingbox"
        }
    }
}
