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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    /// Done sits level with the title and the hint runs under both at the card's full width; at accessibility sizes
    /// Done takes the whole width under the words, so neither it nor the title is broken to fit beside the other.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                title
                hintLine
                doneButton(fullWidth: true)
            } else {
                HStack(spacing: Space.m) {
                    title
                    Spacer(minLength: 0)
                    doneButton(fullWidth: false).fixedSize()
                }
                hintLine
            }
        }
    }

    private var title: some View {
        Text("Decorate")
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
    }

    private var hintLine: some View {
        Text(hint)
            .font(.ourioCaption)
            .foregroundStyle(machine.verdict == .fits ? Ink.textSecondary : Ink.destructive)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func doneButton(fullWidth: Bool) -> some View {
        Button("Done") { done() }
            .buttonStyle(PrimaryButtonStyle(fullWidth: fullWidth))
            .accessibilityIdentifier("decorDone")
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

    /// The chosen piece's controls in two columns of the same width, the turns over Store and Undo, so the pills
    /// line up whatever their words measure; one under another at accessibility sizes.
    private func controls(for id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Catalog.item(id, cat: state.petName)?.name ?? DecorItem.item(shopID: id)?.base?.title ?? id)
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Space.s) {
                    turnButtons
                    keepButtons
                }
            } else {
                Grid(horizontalSpacing: Space.s, verticalSpacing: Space.s) {
                    if machine.canTurn {
                        GridRow { turnButtons }
                    }
                    GridRow { keepButtons }
                }
            }
        }
    }

    @ViewBuilder private var turnButtons: some View {
        if machine.canTurn {
            PillButton("Rotate", symbol: "rotate.right", fullWidth: true) { state.decor.send(.turned) }
                .accessibilityIdentifier("decorRotate")
            PillButton("45°", symbol: "rotate.right", fullWidth: true) { state.decor.send(.turnedFine) }
                .accessibilityIdentifier("decorRotateFine")
        }
    }

    @ViewBuilder private var keepButtons: some View {
        PillButton("Store", symbol: "tray.and.arrow.down", fullWidth: true) { state.decor.send(.stored) }
            .accessibilityIdentifier("decorStore")
        undoButton(fullWidth: true)
    }

    @ViewBuilder private var closet: some View {
        let items = machine.book.closet
        if items.isEmpty {
            VStack(spacing: Space.xs) {
                Image(systemName: "shippingbox")
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.textSecondary)
                    .accessibilityHidden(true)
                Text("The closet is empty")
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
                Text("Everything is in the room. Tap a piece to move, turn or put it away.")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(CardMetrics.padding)
            .cardSurface()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("decorClosetEmpty")
        } else {
            // The whole closet while it fits a few rows; past that it scrolls, so the panel never climbs over the room.
            ViewThatFits(in: .vertical) {
                closetGrid(items)
                ScrollView { closetGrid(items) }
                    .scrollIndicators(.hidden)
                    .ourioScrollEdges()
            }
            .frame(maxHeight: Size.button * 5)
        }
        actionRow
    }

    private func closetGrid(_ items: [DecorItem]) -> some View {
        ItemGrid(columns: Self.closetColumns(at: dynamicTypeSize)) {
            ForEach(items) { item in
                let name = Catalog.item(item.id, cat: state.petName)?.name ?? item.base?.title ?? item.id
                Button { state.decor.send(.closetTapped(item.id)) } label: {
                    VStack(spacing: Space.s) {
                        art(item.id)
                            .aspectRatio(Self.closetArtAspect, contentMode: .fit)
                            .corners(.inner)
                        Text(name)
                            .font(.ourioCallout)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    .padding(CardMetrics.padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cardSurface()
                    .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Place \(name)")
                .accessibilityHint("Stands it in the room")
                .accessibilityIdentifier("decorCloset.\(item.id)")
            }
        }
    }

    /// Two equal tiles across the tray; `ItemGrid` stacks them one to a row at the accessibility sizes.
    static func closetColumns(at size: DynamicTypeSize) -> Int { size.isAccessibilitySize ? 1 : 2 }

    /// Wider than tall, so two rows of the closet stay under the room's floor.
    static let closetArtAspect: CGFloat = 1.6

    @ViewBuilder private func undoButton(fullWidth: Bool) -> some View {
        if machine.book.undo != nil {
            PillButton("Undo", symbol: "arrow.uturn.backward", fullWidth: fullWidth) { state.decor.send(.undone) }
                .accessibilityIdentifier("decorUndo")
        }
    }

    /// Reset and Undo at one width across the panel's insets; one under the other at the accessibility sizes.
    @ViewBuilder private var actionRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Space.s) { actionButtons }
            } else {
                HStack(spacing: Space.s) { actionButtons }
            }
        }
        .confirmationDialog("Put everything back where it first stood? What you bought is placed again where it fits.", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset room", role: .destructive) { state.decor.send(.resetRoom) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var actionButtons: some View {
        PillButton("Reset room", symbol: "arrow.counterclockwise", fullWidth: true) { confirmingReset = true }
            .accessibilityIdentifier("decorReset")
        undoButton(fullWidth: true)
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
