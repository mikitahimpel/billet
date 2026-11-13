import FeatureUs
import MomentsInterface
import WidgetInterface
import WidgetUI
import PhotosUI
import SwiftUI
import Design
import TipKit
import UsInterface

struct TabBar: View {
    let state: HomeState
    /// The finger on the bar, as `TabScrubLayer` reads it: the tab under it is the one shown.
    let scrub: TabScrub
    /// The capsule's frame in `HomeView.space`, where the layer that takes its touches lies over it.
    @Binding var capsule: CGRect

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let tabs = HomeTab.allCases
    static let inset: CGFloat = 6

    /// The tabs only navigate; adding lives in its own button beside them, as iOS 26 places search.
    var body: some View {
        // One container, so the bar and the "+" sample the room together and read as one piece of glass.
        GlassGroup {
            HStack(spacing: GlassMetrics.gap) {
                HStack(spacing: 0) {
                    ForEach(Self.tabs, id: \.self) { tab in
                        switch tab {
                        case .moments: item(tab).hint(MomentsHint(), arrowEdge: .bottom, target: Capsule())
                        case .shop: item(tab).hint(ShopHint(), arrowEdge: .bottom, target: Capsule())
                        case .world, .us: item(tab)
                        }
                    }
                }
                .background(alignment: .leading) { pill }
                .padding(Self.inset)
                .contentShape(.capsule)
                // Without the layer (a game, the perf arm without bars) a tap still never reaches the room.
                .onTapGesture {}
                // The touches are `TabScrubLayer`'s, laid over this frame from outside the bar (see there).
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(HomeView.space)) }) { capsule = $0 }
                .glass(.capsule, role: .bar)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("tabbar")

                AddButton(state: state)
            }
            // The gap between the bar and the "+", and anything else in the row, belongs to the bar: a tap there
            // never reaches the room underneath.
            .background {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture {}
                    .accessibilityHidden(true)
            }
        }
        // A light tap rather than the selection tick, which is too faint to feel through a switch of the whole page.
        .haptic(.tap, trigger: scrub.hovered ?? state.tab)
    }

    /// One pill for the whole row, moved to the selected slot by an offset, so no view comes or goes inside the glass.
    /// It slides while the finger is on the bar; a switch from elsewhere (a link, VoiceOver) moves it at once.
    private var pill: some View {
        GeometryReader { row in
            let slot = row.size.width / CGFloat(Self.tabs.count)
            let selected = scrub.hovered ?? state.tab
            Capsule()
                .fill(Ink.glassSelection)
                .overlay { Capsule().strokeBorder(Ink.selectionRim, lineWidth: 1) }
                .frame(width: slot)
                .modifier(SlidingPill(tab: selected, slides: !reduceMotion))
                .offset(x: slot * CGFloat(selected.order))
        }
    }

    private func item(_ tab: HomeTab) -> some View {
        let shown = (scrub.hovered ?? state.tab) == tab
        let dusk = Look.current == .dusk
        return VStack(spacing: 3) {
            Image(systemName: dusk ? tab.symbol(filled: shown) : tab.symbol)
                .ourioScaledFont(size: 18, weight: .semibold, design: dusk ? .rounded : .default)
            Text(tab.title)
                .ourioScaledFont(size: 11, weight: dusk && shown ? .semibold : .medium, relativeTo: .caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        // The bar keeps its height: past this size its labels show in the large content viewer instead.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .foregroundStyle(shown ? Ink.glassGlyph : Ink.glassGlyphSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .scaleEffect(scrub.hovered == tab ? 1.06 : 1)
        // The drag on the bar does the switching; VoiceOver and the UI tests get each tab as a button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityShowsLargeContentViewer {
            Label(tab.title, systemImage: tab.symbol)
        }
        .accessibilityAddTraits(state.tab == tab ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { state.tab = tab }
    }
}

/// The bar's touches, as a layer over the capsule in the shell's own coordinate space rather than a gesture of the
/// bar's. Like the system tab bar: the tab switches the moment the finger lands on it, or slides onto it, and lifting
/// the finger changes nothing more. A tap lasts about a tenth of a second; a switch that waited for its end would come
/// that late after the pill. The switch re-hosts the bar under the new page's scroll view, which cancels a gesture of
/// the bar's own in the middle of the slide; this layer stays where it is. Should its gesture still be cancelled, the
/// pressed state resets and the slide ends where it is, with the finger's tab already shown.
struct TabScrubLayer: View {
    let state: HomeState
    @Binding var scrub: TabScrub
    let capsule: CGRect
    @GestureState private var pressing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color.clear
            .frame(width: capsule.width, height: capsule.height)
            .contentShape(.capsule)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, pressing, _ in pressing = true }
                    .onChanged { land($0.location.x) }
                    .onEnded { _ in lift() }
            )
            .onChange(of: pressing) { _, pressing in
                if !pressing { lift() }
            }
            .offset(x: capsule.minX, y: capsule.minY)
            .accessibilityHidden(true)
    }

    private func land(_ x: CGFloat) {
        guard let move = scrub.finger(on: tab(at: x), shown: state.tab) else { return }
        withAnimation(follow) { scrub = move.scrub }
        // Outside `withAnimation`: a switch animated as a whole would also fade the room and redraw the glass every
        // frame.
        if let shows = move.shows { state.tab = shows }
    }

    private func lift() {
        guard scrub.hovered != nil else { return }
        withAnimation(follow) { scrub = scrub.lifted() }
    }

    /// The tab whose slot holds `x`, measured from the capsule's leading edge; past the ends it is the first or last.
    private func tab(at x: CGFloat) -> HomeTab {
        HomeTab.at(x - TabBar.inset, across: capsule.width - TabBar.inset * 2) ?? state.tab
    }

    private var follow: Animation { reduceMotion ? Motion.fade() : Motion.spring(Motion.quick) }
}

/// The selection pill glides from tab to tab; under Reduce Motion it fades out of one slot and into the next.
private struct SlidingPill: ViewModifier {
    let tab: HomeTab
    let slides: Bool

    func body(content: Content) -> some View {
        if slides {
            content
        } else {
            content.id(tab).transition(.opacity)
        }
    }
}

// MARK: - Add button

struct AddButton: View {
    let state: HomeState

    private enum Route: Identifiable {
        case moment(UIImage), list(UUID), newList, wish, event, dates

        var id: String {
            switch self {
            case .moment: "moment"
            case .list(let id): "list-\(id)"
            case .newList: "new-list"
            case .wish: "wish"
            case .event: "event"
            case .dates: "dates"
            }
        }
    }

    @State private var route: Route?
    @State private var picking = false
    @State private var pick: PhotosPickerItem?
    @Environment(Hints.self) private var hints

    /// Something was picked from the menu.
    private var adding: Bool { route != nil || picking || state.composingNote != nil }

    var body: some View {
        Menu {
            Button { picking = true } label: {
                Label("Moment · +10", systemImage: "photo.badge.plus")
            }
            Button { state.drawing = true } label: {
                Label("Draw", systemImage: "scribble.variable")
            }
            Button { state.composingNote = .write } label: {
                Label("Note · +5", systemImage: "note.text")
            }
            Menu {
                ForEach(state.us.lists) { list in
                    Button { route = .list(list.id) } label: { Label(list.title, systemImage: list.icon.symbol) }
                }
                Divider()
                Button { route = .newList } label: { Label("New list", systemImage: "plus") }
            } label: {
                Label("To a list", systemImage: "checklist")
            }
            Divider()
            Button { route = .wish } label: {
                Label("Wish", systemImage: "gift")
            }
            Button { route = .event } label: {
                Label("Event", systemImage: "calendar.badge.plus")
            }
            Button { route = .dates } label: {
                Label("Date", systemImage: "heart.text.square")
            }
        } label: {
            Image(systemName: "plus")
                .ourioScaledFont(size: 24, weight: .semibold)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .foregroundStyle(Ink.heroInk)
                .modifier(PlusLook())
        }
        .accentGlass()
        .accessibilityLabel("Add")
        .hint(AddHint(), arrowEdge: .bottom, target: Circle())
        .onChange(of: adding) { _, adding in
            if adding { hints.done(AddHint()) }
        }
        .photosPicker(isPresented: $picking, selection: $pick, matching: .images)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let image = await item.loadImage(maxPixels: MomentStore.storedPixels) {
                    route = .moment(image)
                }
                pick = nil
            }
        }
        .sheet(item: $route) { route in
            switch route {
            case .moment(let image):
                ComposeSheet(image: image) { caption in
                    withAnimation(Motion.spring(0.4)) { _ = state.journal.addMoment(image, caption: caption, shares: true) }
                }
            case .list(let id): ListScreen(state: state, listID: id, focusesField: true)
            case .newList: NewListSheet(state: state) { self.route = .list($0) }
            case .wish: WishEditor(state: state, existing: nil)
            case .event: EventEditor(state: state, event: UsEvent(title: "", icon: UsGlyph.palette[0], date: .now), isNew: true)
            case .dates: DatesScreen(state: state)
            }
        }
    }
}

/// The "+" disc, 66 pt: from iOS 26 the label is just its symbol, sized so the prominent glass around it comes out
/// at 66; before, the label is the disc that `accentGlass` fills.
private struct PlusLook: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.frame(width: 46, height: 46)
        } else {
            content.frame(width: 66, height: 66)
        }
    }
}
