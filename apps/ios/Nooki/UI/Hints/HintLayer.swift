import Design
import SwiftUI
import TipKit

/// Where a hint's control is on screen and which of the card's edges points at it.
struct HintSpot: Equatable {
    let frame: CGRect
    let edge: Edge
}

/// Where the card goes in a layer of `bounds` (global points): across the layer inside its gutters, above the control
/// for an arrow on the card's bottom edge and below it otherwise, the arrow along the edge as near the control's
/// middle as the card's corners let it.
struct HintPlacement: Equatable {
    /// From the layer's edge on the arrow's side to the card's.
    let inset: CGFloat
    let width: CGFloat
    let pointer: CalloutPointer

    init(spot: HintSpot, bounds: CGRect) {
        width = max(bounds.width - 2 * Space.l, 0)
        let gap = Space.s * 2
        let below = spot.edge != .bottom
        inset = below ? spot.frame.maxY - bounds.minY + gap : bounds.maxY - spot.frame.minY + gap
        let run = max(width - 2 * Radius.card, 1)
        let along = (spot.frame.midX - bounds.minX - Space.l - Radius.card) / run
        pointer = CalloutPointer(edge: below ? .top : .bottom, position: along)
    }
}

/// The hint cards over Home, each at the control it is about (`hint(_:arrowEdge:target:)`). Drawn in Home's own
/// hierarchy rather than presented: a sheet or a cover lies over a card the way it lies over the rest of Home, and a
/// card that goes leaves nothing behind to take a touch. A TipKit popover puts a full-screen dismissing view over the
/// app, which a cover closing at the same moment can leave behind without its card, taking every tap.
struct HintLayer: View {
    let hints: Hints
    @State private var bounds = CGRect.zero

    var body: some View {
        ZStack {
            card(PetHint())
            card(NeedsHint())
            card(AddHint())
            card(MomentsHint())
            card(ShopHint())
            card(RoomsHint())
            card(TreatHint())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { bounds = $0 }
    }

    @ViewBuilder private func card<T: HintTip>(_ tip: T) -> some View {
        if let spot = hints.spots[T.hintId], bounds.width > 0 {
            HintCard(tip: tip, hints: hints, placement: HintPlacement(spot: spot, bounds: bounds))
        }
    }
}

/// One hint's card, while TipKit's rules for it hold: the plan staged it and it was neither closed nor done.
private struct HintCard<T: HintTip>: View {
    let tip: T
    let hints: Hints
    let placement: HintPlacement
    @State private var shows = false

    var body: some View {
        let above = placement.pointer.edge == .bottom
        ZStack {
            if shows {
                Callout(close: { hints.close(tip) }) {
                    tip.image
                } title: {
                    tip.title
                } message: {
                    tip.message
                } actions: {
                    EmptyView()
                }
                // Chrome caps its text as the header does, so the card stays clear of the control it points at.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .calloutBubble(pointer: placement.pointer)
                .frame(width: placement.width)
                .onAppear { hints.appeared(tip) }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: above ? .bottom : .top)
        .padding(above ? .bottom : .top, placement.inset)
        .task {
            for await shows in tip.shouldDisplayUpdates {
                withAnimation(Motion.fade()) { self.shows = shows }
            }
        }
    }
}
