#if DEBUG || LABS_YES
import Design
import FeatureFold
import FoldInterface
import SwiftUI
import Wire

/// Fold and draw, the prototype: two people and one phone. The first draws the top half of a creature down to the
/// fold, the second sees only a strip of it and draws the rest, and the sheet opens on what the two made.
struct FoldScreen: View {
    let cat: String

    @State private var store: FoldStore = .fold()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            switch store.state {
            case .drawing(let sketch): drawing(sketch)
            case .folded: passing
            case .opened(let opened): after(opened)
            }
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .bottomActions(primary: { primary }, secondary: { EmptyView() })
        .background(Ink.screen.ignoresSafeArea())
        .navigationTitle("Fold and draw")
        .interactiveDismissDisabled()
    }

    // MARK: Drawing

    private func drawing(_ sketch: FoldMachine.Sketch) -> some View {
        Group {
            Text(title(sketch.half))
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("foldTitle")
            paper(sketch)
                .haptic(.rejected, trigger: sketch.refused)
                .accessibilityIdentifier("foldPaper")
            HStack(spacing: Space.m) {
                PillButton("Undo", symbol: "arrow.uturn.backward") { store.send(.undo) }
                    .disabled(sketch.strokes.isEmpty)
                    .accessibilityIdentifier("foldUndo")
                PillButton("Clear", symbol: "trash") { store.send(.cleared) }
                    .disabled(sketch.strokes.isEmpty)
                    .accessibilityIdentifier("foldClear")
            }
            Text(hint(sketch))
                .font(.ourioCaption)
                .foregroundStyle(sketch.refused == nil ? Ink.textSecondary : Ink.destructive)
                .lineLimit(3, reservesSpace: true)
                .accessibilityIdentifier("foldHint")
        }
    }

    @ViewBuilder private func paper(_ sketch: FoldMachine.Sketch) -> some View {
        let touch: (Point?) -> Void = { point in
            if let point { store.send(.touched(point)) } else { store.send(.lifted) }
        }
        switch sketch.half {
        case .top:
            FoldPaper(strokes: sketch.visible, top: 0, height: FoldRules.half,
                      strip: FoldSheet.peekLine...FoldRules.half, touch: touch)
        case .bottom:
            FoldPaper(strokes: sketch.peek + sketch.visible, top: FoldSheet.peekLine,
                      height: FoldRules.half + FoldRules.peek, strip: FoldSheet.peekLine...FoldRules.half,
                      fold: FoldRules.half, touch: touch)
        }
    }

    private func title(_ half: FoldHalf) -> String {
        switch half {
        case .top: "First: the top half"
        case .bottom: "Second: the bottom half"
        }
    }

    private func hint(_ sketch: FoldMachine.Sketch) -> String {
        switch sketch.refused {
        case .nothingDrawn: return "Nothing is drawn yet."
        case .stopsShortOfTheFold:
            return "Bring a line or two down into the shaded strip, or there is nothing to go on from."
        case nil: break
        }
        switch sketch.half {
        case .top:
            return "Draw the head and shoulders of anything at all, and keep the screen to yourself. Only the "
                + "shaded strip at the bottom will show to the other."
        case .bottom:
            return "The strip above the dashed line is all you get to see. Carry its lines on down into a body "
                + "and legs."
        }
    }

    // MARK: Passing and after

    private var passing: some View {
        Group {
            Text("Folded. Pass the phone")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
            Text("The top half is hidden. Whoever draws next sees only where its lines reach the fold.")
                .font(.ourioBody)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("foldPass")
        }
    }

    private func after(_ opened: FoldMachine.Opened) -> some View {
        Group {
            Text("\(cat) has a good look and names it \(opened.creature.name).")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .accessibilityIdentifier("foldName")
            FoldPaper(strokes: opened.creature.strokes, top: 0, height: 2 * FoldRules.half)
                .haptic(.tap, trigger: opened.round)
        }
    }

    // MARK: Actions

    @ViewBuilder private var primary: some View {
        switch store.state {
        case .drawing(let sketch):
            switch sketch.half {
            case .top:
                PrimaryButton("Fold it and hand over", symbol: "arrow.left.arrow.right") { store.send(.done) }
                    .accessibilityIdentifier("foldDone")
            case .bottom:
                PrimaryButton("Open the sheet", symbol: "doc.richtext") { store.send(.done) }
                    .accessibilityIdentifier("foldDone")
            }
        case .folded:
            PrimaryButton("I have it", symbol: "hand.raised.fill") { store.send(.took) }
                .accessibilityIdentifier("foldTook")
        case .opened:
            PrimaryButton("Swap and draw another", symbol: "arrow.triangle.2.circlepath") { store.send(.again) }
                .accessibilityIdentifier("foldAgain")
        }
    }
}
#endif
