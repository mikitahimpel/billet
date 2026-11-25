#if DEBUG || LABS_YES
import Design
import FeaturePack
import PackInterface
import SwiftUI

/// Pack for two, the prototype: two people and one phone. The first packs three things into the suitcase knowing
/// only the names of the other's; the second fits theirs round them, and the cat goes in last if there is room.
struct PackScreen: View {
    let cat: String

    @State private var store: PackStore

    init(cat: String, seed: UInt64) {
        self.cat = cat
        _store = State(initialValue: .pack(seed: seed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            switch store.state {
            case .packing(let turn): packing(turn)
            case .handover(let handover): passing(handover)
            case .closed(let closed): after(closed)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bottomActions(primary: { primary }, secondary: { secondary })
        .background(Ink.screen.ignoresSafeArea())
        .navigationTitle("Pack for two")
    }

    // MARK: Packing

    private func packing(_ turn: PackMachine.Turn) -> some View {
        Group {
            Text(title(turn))
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("packTitle")
            PackBoardCanvas(suitcase: turn.suitcase) { store.send(.tapped($0)) }
                .haptic(.tap, trigger: turn.suitcase.placed.count)
                .haptic(.rejected, trigger: turn.refused)
                .accessibilityIdentifier("packBoard")
            FlowRow {
                ForEach(turn.tray) { piece in
                    FilterChip("\(PackLook.title(piece, cat: cat)) · \(piece.shape.cells.count)",
                               isSelected: turn.held?.id == piece.id) {
                        store.send(.picked(piece.id))
                    }
                    .accessibilityIdentifier("packPiece\(piece.id)")
                }
            }
            if let piece = turn.heldPiece, let held = turn.held {
                HStack(spacing: Space.m) {
                    PackShapeGlyph(shape: piece.shape.turned(held.turns), color: PackLook.color(piece))
                    PillButton("Turn", symbol: "rotate.right") { store.send(.turned) }
                        .accessibilityIdentifier("packTurn")
                    PillButton("Put back", symbol: "arrow.uturn.backward") { store.send(.dropped) }
                        .accessibilityIdentifier("packDrop")
                }
            } else {
                PillButton("Ask \(cat)", symbol: "nose.fill") { store.send(.askedCat) }
                    .accessibilityIdentifier("packAsk")
            }
            Text(hint(turn))
                .font(.ourioCaption)
                .foregroundStyle(turn.refused == nil ? Ink.textSecondary : Ink.destructive)
                .lineLimit(3, reservesSpace: true)
                .accessibilityIdentifier("packHint")
        }
    }

    private func title(_ turn: PackMachine.Turn) -> String {
        switch turn.packer {
        case .first: turn.game.repacks == 0 ? "First packer: your three things" : "First packer: pack it again"
        case .second: "Second packer: yours, then \(cat)"
        }
    }

    private func hint(_ turn: PackMachine.Turn) -> String {
        switch turn.refused {
        case .sticksOut: return "It would stick out of the suitcase."
        case .onTop: return "Something already lies there."
        case nil: break
        }
        switch turn.nose {
        case .fits: return "\(cat) sniffs the suitcase and purrs: everything still to come can go in."
        case .tooTight: return "\(cat) sniffs and looks doubtful: packed like this, something will not fit."
        case nil: break
        }
        if turn.held != nil { return "Tap a square of the suitcase and it lies down over it, if there is a way." }
        switch turn.packer {
        case .first:
            let names = turn.unseen.map { PackLook.title($0, cat: cat) }.formatted(.list(type: .and))
            return "Still to come from the other: \(names), then \(cat). You know the names, not the shapes. "
                + "Tap a thing to pick it up; tap one in the suitcase to take it out."
        case .second:
            return "Fit your three round what is there. \(cat) goes in last if there is room, and sits on the lid "
                + "if there is not."
        }
    }

    // MARK: Passing and after

    private func passing(_ handover: PackMachine.Handover) -> some View {
        Group {
            Text("Pass the phone")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            Text(handover.to == .second
                ? "Second packer: three things of yours and \(cat) still have to go in. You may not move what is "
                    + "packed already."
                : "It will not go. First packer: your things are as you left them, and now you have seen what "
                    + "has to fit round them.")
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("packPass")
        }
    }

    private func after(_ closed: PackMachine.Closed) -> some View {
        Group {
            Text(verdict(closed))
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("packVerdict")
            PackBoardCanvas(suitcase: closed.suitcase) { _ in }
            Text(closed.game.repacks == 0
                ? "Packed in one go."
                : "Packed after sending it back \(closed.game.repacks) time\(closed.game.repacks == 1 ? "" : "s").")
                .font(.ourioCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func verdict(_ closed: PackMachine.Closed) -> String {
        switch closed.ending {
        case .snug: "Zipped. \(cat) is in there too, and coming with you."
        case .catOnTop: "Zipped, with \(cat) sitting on the lid and coming anyway."
        }
    }

    // MARK: Actions

    @ViewBuilder private var primary: some View {
        switch store.state {
        case .packing(let turn):
            switch turn.packer {
            case .first:
                PrimaryButton("Hand the phone over", symbol: "arrow.left.arrow.right") { store.send(.handedOver) }
                    .disabled(!turn.canHandOver)
                    .accessibilityIdentifier("packHandOver")
            case .second:
                PrimaryButton("Zip it up", symbol: "suitcase.fill") { store.send(.zipped) }
                    .disabled(!turn.canClose)
                    .accessibilityIdentifier("packZip")
            }
        case .handover:
            PrimaryButton("I have it", symbol: "hand.raised.fill") { store.send(.took) }
                .accessibilityIdentifier("packTook")
        case .closed:
            PrimaryButton("Swap and pack the next one", symbol: "arrow.triangle.2.circlepath") {
                store.send(.again)
            }
            .accessibilityIdentifier("packAgain")
        }
    }

    @ViewBuilder private var secondary: some View {
        switch store.state {
        case .packing(let turn):
            switch turn.packer {
            case .first:
                EmptyView()
            case .second:
                SecondaryButton("It will not go: send it back", symbol: "arrow.uturn.left") {
                    store.send(.sentBack)
                }
                .accessibilityIdentifier("packSendBack")
            }
        case .handover, .closed:
            EmptyView()
        }
    }
}
#endif
