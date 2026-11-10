import OurioShared
import SwiftUI
import Design
import Wire

struct ListScreen: View {
    let state: HomeState
    let listID: UUID
    /// Opened from the "+" menu to add an item, so the keyboard comes up at once.
    var focusesField = false

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var renaming = false
    @State private var confirmingDelete = false
    @State private var reward: UUID?
    @State private var rewardRising = false
    @State private var editing: ListItem?
    @State private var watchDetails = WatchDetails()
    @State private var addingTitle = false
    @State private var openedTitle: OpenedTitle?
    @State private var addingPlace = false
    @State private var markingBeen: ListItem?
    @FocusState private var focused: Bool

    private struct OpenedTitle: Identifiable {
        let id: UUID
    }

    var body: some View {
        Group {
            if let list = state.us.list(listID) {
                content(list)
            } else {
                BilletSheet("List", size: .fit) {
                    EmptyState(icon: .init(symbol: "basket.fill", tint: .sage), title: "Nothing here yet", text: "This list is gone.")
                }
            }
        }
    }

    private func content(_ list: UsList) -> some View {
        BilletSheet(list.title, subtitle: subtitle(of: list), scrolls: false) {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    if adding(to: list) {
                        GrocerySuggestions(draft: draft, list: list, history: state.us.groceries) {
                            add($0, to: list)
                        }
                    }
                    if list.kind == .watch {
                        WatchListBody(state: state, list: list, details: watchDetails) {
                            openedTitle = OpenedTitle(id: $0.id)
                        }
                    } else if list.kind == .travel {
                        PlacesListBody(state: state, list: list) { markingBeen = $0 }
                    } else if list.items.isEmpty {
                        if !adding(to: list) {
                            EmptyState(icon: list.icon,
                                    title: "Nothing here yet",
                                    text: "Add the first one above. You both see this list.")
                        }
                    } else if list.kind.isChecklist {
                        // While a name is typed, its suggestions take the screen, as the list would push them away.
                        if draft.isEmpty {
                            GroceryList(list: list, state: state,
                                        onTap: { toggle($0, in: list) },
                                        onEdit: { editing = $0 },
                                        onClear: {
                                            withAnimation(.snappy(duration: 0.25)) { state.us.clearDone(in: listID) }
                                        })
                        }
                    } else {
                        openCard(list)
                        finishedSection(list)
                    }
                }
                .id(Self.top)
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl + Space.s)
            }
            .scrollIndicators(.hidden)
            .onChange(of: focused) { _, focused in
                if focused { withAnimation(.snappy(duration: 0.25)) { scroll.scrollTo(Self.top, anchor: .top) } }
            }
        }
        .scrollHeader {
            VStack(spacing: 0) {
                if !usesSheetToAdd(list) {
                    UsField(placeholder: placeholder(for: list.kind), text: $draft)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { addItem(list) }
                        .onAppear { if focusesField { focused = true } }
                        .padding(.horizontal, Space.gutter)
                        .padding(.top, Space.l)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if list.kind == .watch {
                    Button { addingTitle = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add")
                } else if list.kind == .travel {
                    Button { addingPlace = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add")
                }
                Menu {
                    Button("Rename") { renaming = true }
                    Button("Delete list", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("List options")
            }
        }
        }
        .onAppear {
            guard focusesField else { return }
            if list.kind == .watch { addingTitle = true }
            if list.kind == .travel { addingPlace = true }
        }
        .sheet(item: $editing) { item in
            GroceryItemSheet(state: state, listID: listID, item: item)
        }
        .sheet(isPresented: $renaming) {
            RenameListSheet(state: state, list: list)
        }
        .sheet(isPresented: $addingTitle) {
            AddTitleSheet(state: state, listID: listID)
        }
        .sheet(isPresented: $addingPlace) {
            AddPlaceSheet(state: state, listID: listID)
        }
        .sheet(item: $markingBeen) { item in
            BeenSheet(state: state, listID: listID, item: item)
        }
        .sheet(item: $openedTitle) { opened in
            MovieCard(state: state, listID: listID, itemID: opened.id, details: watchDetails)
        }
        .confirmationDialog("Delete this list?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete list", role: .destructive) {
                state.us.deleteList(listID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It disappears for both of you.")
        }
    }

    private static let top = "top"

    private func adding(to list: UsList) -> Bool { list.kind.isChecklist && focused }

    private func usesSheetToAdd(_ list: UsList) -> Bool { list.kind == .watch || list.kind == .travel }

    private func subtitle(of list: UsList) -> String {
        if list.kind.isChecklist { return "\(list.open.count) to buy" }
        if list.kind == .travel {
            let rows = PlaceRow.rows(of: list)
            return "\(rows.want.count) to go · \(rows.been.count) been"
        }
        if list.kind == .watch { return "\(list.open.count) to go · \(list.finished.count) watched" }
        return "\(list.open.count) to go · \(list.finished.count) done"
    }

    private func placeholder(for kind: ListKind) -> String {
        switch kind {
        case .watch: "Add a movie or show…"
        case .groceries: "Add something to buy…"
        case .travel: "Add a place…"
        case .food: "Add a place to eat…"
        case .books: "Add a book…"
        case .bucket: "Add a dream…"
        case .custom: "Add an item…"
        }
    }

    private func addItem(_ list: UsList) {
        add(draft, to: list)
    }

    /// A grocery the pair moved to another aisle before goes there again.
    private func add(_ text: String, to list: UsList) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var details = ListItemDetails()
        if list.kind.isChecklist { details.aisle = state.us.groceries.entry(for: text)?.aisle }
        withAnimation(.snappy(duration: 0.25)) {
            state.us.addItem(text, to: listID, author: state.viewer, details: details)
        }
        draft = ""
        focused = true
    }

    private func openCard(_ list: UsList) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.open.enumerated()), id: \.element.id) { index, item in
                if index > 0 { divider }
                itemRow(item, list: list, doneStyle: false)
            }
        }
        .cardSurface()
    }

    @ViewBuilder
    private func finishedSection(_ list: UsList) -> some View {
        if !list.finished.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Done together")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.top, Space.s)
                VStack(spacing: 0) {
                    ForEach(Array(list.finished.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { divider }
                        itemRow(item, list: list, doneStyle: true, showDate: true)
                    }
                }
                .cardSurface()
            }
        }
    }

    private func itemRow(_ item: ListItem, list: UsList, doneStyle: Bool, showDate: Bool = false) -> some View {
        HStack(spacing: Space.m) {
            checkButton(item, list: list, done: item.done != nil)
            UsIcon(glyph: ItemIcon.glyph(for: item.text, list: list.icon), size: 30)
                .opacity(doneStyle ? 0.55 : 1)
            Text(item.text)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .strikethrough(doneStyle)
                .opacity(doneStyle ? 0.55 : 1)
            Spacer(minLength: 8)
            if showDate, let done = item.done {
                Text(done.formatted(.dateTime.day().month()))
                    .font(.ourioMicro)
                    .foregroundStyle(Ink.textSecondary)
            }
            Monogram(partner: item.author, profile: state.profile, size: 20)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: Size.button)
        .contentShape(.rect)
        .contextMenu {
            Button("Delete", role: .destructive) {
                withAnimation(.snappy(duration: 0.25)) { state.us.deleteItem(item.id, in: listID) }
            }
        }
        .overlay(alignment: .trailing) {
            if reward == item.id { rewardBadge }
        }
    }

    private func checkButton(_ item: ListItem, list: UsList, done: Bool) -> some View {
        Button {
            toggle(item, in: list)
        } label: {
            UsCheck(done: done)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(done ? "Mark as not done" : "Mark as done")
    }

    private func toggle(_ item: ListItem, in list: UsList) {
        let ticking = item.done == nil
        withAnimation(.snappy(duration: 0.25)) {
            state.us.toggleItem(item.id, in: listID, by: state.viewer)
        }
        guard ticking, !list.kind.isChecklist else { return }
        reward = item.id
        rewardRising = false
        withAnimation(.easeOut(duration: 1)) { rewardRising = true }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if reward == item.id {
                withAnimation(.easeOut(duration: 0.2)) { reward = nil }
            }
        }
    }

    private var rewardBadge: some View {
        Label("+5", systemImage: "star.fill")
            .font(.ourioMicro)
            .foregroundStyle(Color.honey)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Color.honey.opacity(0.18), in: .capsule)
            .offset(y: rewardRising ? -26 : 0)
            .opacity(rewardRising ? 0 : 1)
            .padding(.trailing, 46)
            .allowsHitTesting(false)
    }

    private var divider: some View {
        Divider().overlay(Ink.separator).padding(.leading, 94)
    }
}

private struct RenameListSheet: View {
    let state: HomeState
    let list: UsList

    @Environment(\.dismiss) private var dismiss
    @State private var icon: UsGlyph
    @State private var title: String

    init(state: HomeState, list: UsList) {
        self.state = state
        self.list = list
        _icon = State(initialValue: list.icon)
        _title = State(initialValue: list.title)
    }

    var body: some View {
        BilletSheet("Rename list", size: .fit, onConfirm: save) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.m) {
                    UsIcon(glyph: icon, size: 50)
                    UsField(placeholder: "List name", text: $title)
                }
                UsGlyphPicker(selection: $icon)
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        state.us.renameList(list.id, title: name.isEmpty ? list.title : name, icon: icon)
        dismiss()
    }
}

struct NewListSheet: View {
    let state: HomeState
    var onCreate: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var icon = ListKind.custom.icon
    @State private var name = ""

    private var templates: [ListKind] {
        ListKind.allCases.filter { kind in
            kind != .custom && !state.us.lists.contains { $0.kind == kind }
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        BilletSheet("New list", size: .mediumLarge, onConfirm: createCustom, canConfirm: canCreate) {
        VStack(alignment: .leading, spacing: Space.l) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
                ForEach(templates) { kind in
                    Button {
                        create(kind: kind, title: kind.defaultTitle, icon: kind.icon)
                    } label: {
                        VStack(spacing: Space.s) {
                            UsIcon(glyph: kind.icon, size: 40)
                            Text(kind.defaultTitle)
                                .font(.ourioMicro)
                                .foregroundStyle(Ink.text)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .cardSurface()
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }

            Text("Or make your own")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
                .padding(.top, Space.xs)

            HStack(spacing: Space.m) {
                UsIcon(glyph: icon, size: 50)
                UsField(placeholder: "List name", text: $name)
            }
            UsGlyphPicker(selection: $icon)
        }
        }
    }

    private func createCustom() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        create(kind: .custom, title: title, icon: icon)
    }

    private func create(kind: ListKind, title: String, icon: UsGlyph) {
        let list = state.us.addList(kind: kind, title: title, icon: icon)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onCreate(list.id)
        }
    }
}
