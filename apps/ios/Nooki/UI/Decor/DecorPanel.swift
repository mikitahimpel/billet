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
            VStack(alignment: .leading, spacing: 0) {
                header
                if let selected {
                    controls(for: selected)
                        .padding(.top, Space.m)
                } else {
                    closet
                        .padding(.top, Space.m)
                    actionRow
                        .padding(.top, Space.l)
                }
            }
        }
        // One geometry for the card and everything on it: the tiles ride the panel's transition instead of
        // animating to their own frames inside it.
        .geometryGroup()
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.m)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("decorPanel")
    }

    /// Done sits level with the title and the hint runs under both at the card's full width; at accessibility sizes
    /// Done takes the whole width under the words, so neither it nor the title is broken to fit beside the other.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
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

    /// As tall as the closet up to the cap, so the panel hugs a short closet and scrolls a long one; on a short screen
    /// at the largest text it gives up its height first, so the title row and the actions stay on the screen.
    private var closet: some View {
        HeightCap(Self.closetCap, floor: Self.closetFloor) {
            ScrollView {
                let items = machine.book.closet
                if items.isEmpty {
                    emptyCloset
                } else {
                    closetGrid(items)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .ourioScrollEdges()
        }
    }

    private var emptyCloset: some View {
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("decorClosetEmpty")
    }

    private func closetGrid(_ items: [DecorItem]) -> some View {
        ItemGrid(columns: Self.closetColumns(at: dynamicTypeSize)) {
            ForEach(items) { item in
                let name = Catalog.item(item.id, cat: state.petName)?.name ?? item.base?.title ?? item.id
                Button { state.decor.send(.closetTapped(item.id)) } label: {
                    VStack(spacing: Space.s) {
                        art(item.id)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(Self.closetArtAspect, contentMode: .fit)
                        Text(name)
                            .font(.ourioCallout)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2, reservesSpace: true)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .wellSurface(.inner)
                    .contentShape(.containerRelative)
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

    /// The closet's tallest: about a row and a half of tiles, so a third row shows it scrolls.
    static let closetCap: CGFloat = Size.button * 5

    /// The least the closet keeps when the screen is short: a tile's worth to see and scroll.
    static let closetFloor: CGFloat = Size.button * 2

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

    /// Decoded while the panel is built, so the art is drawn in the panel's first frame; a piece without a picture
    /// gets its symbol in the same box.
    @ViewBuilder private func art(_ id: String) -> some View {
        if let image = Thumbnails.image("Item_\(id)", maxPixels: 256) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: Self.symbol(id))
                .font(.ourioTitle)
                .foregroundStyle(Ink.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// Its content at the height it asks for with the width given, no taller than `cap` or than the height offered, and
/// no shorter than `floor` while the content is taller. The most flexible child of a stack, so it takes what is left.
private struct HeightCap: Layout {
    let cap: CGFloat
    let floor: CGFloat

    init(_ cap: CGFloat, floor: CGFloat) {
        self.cap = cap
        self.floor = floor
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)).height
        let offered = proposal.height ?? .infinity
        let height = max(min(natural, cap, offered), min(natural, floor))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
