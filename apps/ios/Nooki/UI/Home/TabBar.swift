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
    /// The tab under the finger while it drags along the bar; the selection follows it and switches on release.
    @State private var hovered: HomeTab?
    @State private var barWidth: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let tabs = HomeTab.allCases
    private static let inset: CGFloat = 6

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
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { barWidth = $0 }
                // Like the system tab bar: touch down anywhere on the capsule, slide the selection along under the
                // finger, switch on release. A plain tap is the same gesture without the slide.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let tab = tab(at: drag.location.x)
                            if tab != hovered { withAnimation(follow) { hovered = tab } }
                        }
                        .onEnded { drag in
                            withAnimation(follow) { hovered = nil }
                            // Outside `withAnimation`: the selection is already on this tab, under the finger, and a
                            // switch animated as a whole would also fade the room and redraw the glass every frame.
                            state.tab = tab(at: drag.location.x)
                        }
                )
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
        .haptic(.tap, trigger: hovered ?? state.tab)
    }

    /// The tab whose slot holds `x`, measured from the capsule's leading edge; past the ends it is the first or last.
    private func tab(at x: CGFloat) -> HomeTab {
        HomeTab.at(x - Self.inset, across: barWidth - Self.inset * 2) ?? state.tab
    }

    private var follow: Animation { reduceMotion ? Motion.fade() : Motion.spring(Motion.quick) }

    /// One pill for the whole row, moved to the selected slot by an offset, so no view comes or goes inside the glass.
    /// It slides while the finger is on the bar; a switch from elsewhere (a link, VoiceOver) moves it at once.
    private var pill: some View {
        GeometryReader { row in
            let slot = row.size.width / CGFloat(Self.tabs.count)
            let selected = hovered ?? state.tab
            Capsule()
                .fill(Ink.glassSelection)
                .frame(width: slot)
                .modifier(SlidingPill(tab: selected, slides: !reduceMotion))
                .offset(x: slot * CGFloat(selected.order))
        }
    }

    private func item(_ tab: HomeTab) -> some View {
        let shown = (hovered ?? state.tab) == tab
        return VStack(spacing: 3) {
            Image(systemName: tab.symbol).ourioScaledFont(size: 18, weight: .semibold)
            Text(tab.title).ourioScaledFont(size: 11, weight: .medium, relativeTo: .caption2)
        }
        // The bar keeps its height: past this size its labels show in the large content viewer instead.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .foregroundStyle(shown ? Ink.glassGlyph : Ink.glassGlyphSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .scaleEffect(hovered == tab ? 1.06 : 1)
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
                Label("Moment", systemImage: "photo.badge.plus")
                Text("Photo for the wall · +10")
            }
            Button { state.drawing = true } label: {
                Label("Draw", systemImage: "scribble.variable")
                Text("On \(state.otherPartner)'s lock screen")
            }
            Button { state.composingNote = .write } label: {
                Label("Note", systemImage: "note.text")
                Text("On the board · +5")
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
                Text("On your wishlist")
            }
            Button { route = .event } label: {
                Label("Event", systemImage: "calendar.badge.plus")
                Text("On the shared calendar")
            }
            Button { route = .dates } label: {
                Label("Date", systemImage: "heart.text.square")
                Text("Find an idea or plan one")
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
                    withAnimation(.spring(duration: 0.4)) { _ = state.journal.addMoment(image, caption: caption, shares: true) }
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
