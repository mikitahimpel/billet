import PhotosUI
import SwiftUI

struct TabBar: View {
    let state: HomeState
    @Namespace private var selection
    /// The tab under the finger while it drags along the bar; the selection follows it and switches on release.
    @State private var hovered: HomeTab?
    @State private var barWidth: CGFloat = 0

    private static let tabs: [(tab: HomeTab, title: String, symbol: String)] = [
        (.world, "World", "house.fill"),
        (.moments, "Moments", "photo.on.rectangle"),
        (.shop, "Shop", "bag"),
    ]
    private static let inset: CGFloat = 6

    /// The tabs only navigate; adding lives in its own button beside them, as iOS 26 places search.
    var body: some View {
        // One container, so the bar and the "+" sample the room together and read as one piece of glass.
        GlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(Self.tabs, id: \.tab) { item($0.tab, $0.title, $0.symbol) }
                }
                .padding(Self.inset)
                .contentShape(.capsule)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { barWidth = $0 }
                // Like the system tab bar: touch down anywhere on the capsule, slide the selection along under the
                // finger, switch on release. A plain tap is the same gesture without the slide.
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let tab = tab(at: drag.location.x)
                            if tab != hovered { withAnimation(.snappy(duration: 0.2)) { hovered = tab } }
                        }
                        .onEnded { drag in
                            let tab = tab(at: drag.location.x)
                            withAnimation(.spring(duration: 0.35)) {
                                hovered = nil
                                state.tab = tab
                            }
                        }
                )
                .warmGlass(.capsule, interactive: true)
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
        .sensoryFeedback(.selection, trigger: hovered ?? state.tab)
    }

    /// The tab whose slot holds `x`, measured from the capsule's leading edge; past the ends it is the first or last.
    private func tab(at x: CGFloat) -> HomeTab {
        let slot = (barWidth - Self.inset * 2) / CGFloat(Self.tabs.count)
        guard slot > 0 else { return state.tab }
        let index = Int(((x - Self.inset) / slot).rounded(.down))
        return Self.tabs[min(max(index, 0), Self.tabs.count - 1)].tab
    }

    private func item(_ tab: HomeTab, _ title: String, _ symbol: String) -> some View {
        let shown = (hovered ?? state.tab) == tab
        return VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(shown ? Ink.primary : Ink.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background {
            if shown {
                Capsule()
                    .fill(Color.honey.opacity(hovered == nil ? 0.32 : 0.42))
                    .matchedGeometryEffect(id: "tab", in: selection)
            }
        }
        .scaleEffect(hovered == tab ? 1.06 : 1)
        // The drag on the bar does the switching; VoiceOver and the UI tests get each tab as a button.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(state.tab == tab ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { withAnimation(.spring(duration: 0.35)) { state.tab = tab } }
    }
}

// MARK: - Add button

/// The "+" beside the tab bar: everything the couple adds themselves, from any tab, through the same sheets their tabs use.
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

    var body: some View {
        Menu {
            Button { picking = true } label: {
                Label("Moment", systemImage: "photo.badge.plus")
                Text("Photo for the wall · +10")
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .modifier(PlusLook())
        }
        .modifier(PlusGlass())
        .accessibilityLabel("Add")
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
                    withAnimation(.spring(duration: 0.4)) { _ = state.addMoment(image, caption: caption) }
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

/// The "+" disc: before iOS 26 a solid honey gradient with a soft shadow. From iOS 26 the label is just its symbol,
/// sized so the prominent glass around it comes out at the same 66 pt.
private struct PlusLook: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.frame(width: 46, height: 46)
        } else {
            content
                .frame(width: 66, height: 66)
                .background(.honeyGradient, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .honeyDeep.opacity(0.45), radius: 8, y: 3)
        }
    }
}

/// Honey-tinted prominent glass from iOS 26, the system's look for the one main action beside a tab bar.
private struct PlusGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .menuStyle(.button)
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.honey)
        } else {
            content
        }
    }
}
