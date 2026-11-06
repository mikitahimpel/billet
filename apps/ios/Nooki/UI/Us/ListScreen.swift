import SwiftUI

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
    @State private var watchDetails = WatchDetails()
    @State private var addingTitle = false
    @State private var openedTitle: OpenedTitle?
    @FocusState private var focused: Bool

    private struct OpenedTitle: Identifiable {
        let id: UUID
    }

    var body: some View {
        Group {
            if let list = state.us.list(listID) {
                content(list)
            } else {
                UsEmpty(icon: .init(symbol: "basket.fill", tint: .sage), title: "Nothing here yet", text: "This list is gone.")
                    .usSheet()
            }
        }
    }

    private func content(_ list: UsList) -> some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: list.title, subtitle: subtitle(of: list)) {
                if list.kind == .watch {
                    UsAddButton { addingTitle = true }
                }
                Menu {
                    Button("Rename") { renaming = true }
                    Button("Delete list", role: .destructive) { confirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Ink.surfaceRaised))
                }
                .accessibilityLabel("List options")
            }

            if list.kind != .watch {
                UsField(placeholder: placeholder(for: list.kind), text: $draft)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { addItem(list) }
                    .onAppear { if focusesField { focused = true } }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if list.kind == .watch {
                        WatchListBody(state: state, list: list, details: watchDetails) {
                            openedTitle = OpenedTitle(id: $0.id)
                        }
                    } else if list.items.isEmpty {
                        UsEmpty(icon: list.icon,
                                title: "Nothing here yet",
                                text: "Add the first one above. You both see this list.")
                    } else if list.kind.isChecklist {
                        checklist(list)
                    } else {
                        openCard(list)
                        finishedSection(list)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .usSheet()
        .onAppear { if focusesField && list.kind == .watch { addingTitle = true } }
        .sheet(isPresented: $renaming) {
            RenameListSheet(state: state, list: list)
        }
        .sheet(isPresented: $addingTitle) {
            AddTitleSheet(state: state, listID: listID)
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

    private func subtitle(of list: UsList) -> String {
        if list.kind.isChecklist { return "\(list.open.count) left" }
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
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            state.us.addItem(text, to: listID, author: state.viewer)
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
        .usCard()
    }

    private func checklist(_ list: UsList) -> some View {
        let done = list.finished
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array((list.open + done).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { divider }
                    itemRow(item, list: list, doneStyle: item.done != nil)
                }
            }
            .usCard()

            if !done.isEmpty {
                Button("Clear bought") {
                    withAnimation(.snappy(duration: 0.25)) { state.us.clearDone(in: listID) }
                }
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Color.honey)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func finishedSection(_ list: UsList) -> some View {
        if !list.finished.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Done together")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(list.finished.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { divider }
                        itemRow(item, list: list, doneStyle: true, showDate: true)
                    }
                }
                .usCard()
            }
        }
    }

    private func itemRow(_ item: ListItem, list: UsList, doneStyle: Bool, showDate: Bool = false) -> some View {
        HStack(spacing: 12) {
            checkButton(item, list: list, done: item.done != nil)
            Text(item.text)
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
                .strikethrough(doneStyle)
                .opacity(doneStyle ? 0.55 : 1)
            Spacer(minLength: 8)
            if showDate, let done = item.done {
                Text(done.formatted(.dateTime.day().month()))
                    .font(.nookiMicro)
                    .foregroundStyle(Ink.textSecondary)
            }
            Monogram(partner: item.author, profile: state.profile, size: 20)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
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
            ZStack {
                Circle()
                    .strokeBorder(done ? .clear : Ink.textSecondary, lineWidth: 1.5)
                if done {
                    Circle().fill(Color.honey)
                    Image(systemName: "checkmark")
                        .font(.nookiMicro)
                        .foregroundStyle(Ink.heroInk)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
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
            .font(.nookiMicro)
            .foregroundStyle(Color.honey)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.honey.opacity(0.18), in: .capsule)
            .offset(y: rewardRising ? -26 : 0)
            .opacity(rewardRising ? 0 : 1)
            .padding(.trailing, 46)
            .allowsHitTesting(false)
    }

    private var divider: some View {
        Divider().overlay(Ink.separator).padding(.leading, 52)
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename list")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
            HStack(spacing: 10) {
                UsIcon(glyph: icon, size: 50)
                UsField(placeholder: "List name", text: $title)
            }
            UsGlyphPicker(selection: $icon)
            UsPrimaryButton(title: "Save") {
                let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                state.us.renameList(list.id,
                                    title: name.isEmpty ? list.title : name,
                                    icon: icon)
                dismiss()
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .usSheet(detents: [.medium, .large])
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
        VStack(alignment: .leading, spacing: 16) {
            Text("New list")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(templates) { kind in
                    Button {
                        create(kind: kind, title: kind.defaultTitle, icon: kind.icon)
                    } label: {
                        VStack(spacing: 6) {
                            UsIcon(glyph: kind.icon, size: 40)
                            Text(kind.defaultTitle)
                                .font(.nookiMicro)
                                .foregroundStyle(Ink.text)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .usCard(radius: 18)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Or make your own")
                .font(.nookiHeadline)
                .foregroundStyle(Ink.textSecondary)
                .padding(.top, 4)

            HStack(spacing: 10) {
                UsIcon(glyph: icon, size: 50)
                UsField(placeholder: "List name", text: $name)
            }
            UsGlyphPicker(selection: $icon)

            UsPrimaryButton(title: "Create") {
                createCustom()
            }
            .opacity(canCreate ? 1 : 0.5)
            .allowsHitTesting(canCreate)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .usSheet(detents: [.medium, .large])
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
