import SwiftUI
import Design

struct GroceryList: View {
    let list: UsList
    let state: HomeState
    var onTap: (ListItem) -> Void
    var onEdit: (ListItem) -> Void
    var onClear: () -> Void

    private let catalog = GroceryCatalog.bundled

    var body: some View {
        let history = state.us.groceries
        let open = list.open.map { ($0, catalog.aisle(for: $0, history: history)) }
        let aisles = GroceryAisle.allCases.filter { aisle in open.contains { $0.1 == aisle } }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(aisles) { aisle in
                let items = open.filter { $0.1 == aisle }.map(\.0)
                GrocerySectionLabel(title: aisle.title, icon: aisle.icon, top: aisle == aisles.first ? 4 : 18) {
                    Text("\(items.count)")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textTertiary)
                }
                card(items, done: false)
            }
            let bought = list.finished
            if !bought.isEmpty {
                GrocerySectionLabel(title: "Bought", top: open.isEmpty ? 4 : 18) {
                    Button("Clear", action: onClear)
                        .font(.ourioCallout.weight(.semibold))
                        .foregroundStyle(Ink.accentText)
                        .buttonStyle(.plain)
                }
                card(bought, done: true)
            }
        }
    }

    private func card(_ items: [ListItem], done: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 52) }
                GroceryRow(item: item, profile: state.profile, done: done)
                    .onTapGesture { onTap(item) }
                    .onLongPressGesture(minimumDuration: 0.35) { onEdit(item) }
                    .accessibilityAction { onTap(item) }
                    .accessibilityAction(named: "Edit") { onEdit(item) }
            }
        }
        .cardSurface()
    }
}

struct GrocerySectionLabel<Trailing: View>: View {
    let title: String
    var icon: UsGlyph?
    var top: CGFloat = 18
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let icon { UsIcon(glyph: icon, size: 26) }
            Text(title)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 2)
        .padding(.top, top)
        .padding(.bottom, 8)
    }
}

extension GrocerySectionLabel where Trailing == EmptyView {
    init(title: String, top: CGFloat = 18) {
        self.init(title: title, top: top) { EmptyView() }
    }
}

struct GroceryRow: View {
    let item: ListItem
    let profile: CoupleStore
    var done = false

    var body: some View {
        HStack(spacing: 12) {
            UsCheck(done: done)
            Text(item.text)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.text)
                .strikethrough(done)
                .lineLimit(2)
            Spacer(minLength: 8)
            let quantity = item.quantity.map { $0.allSatisfy(\.isNumber) ? "×\($0)" : $0 }
            let detail = [quantity, item.note].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
            if !detail.isEmpty {
                Text(detail)
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
            }
            if !item.author.isEmpty {
                Monogram(partner: item.author, profile: profile, size: 20)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .opacity(done ? 0.55 : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.text, item.quantity, item.note].compactMap(\.self).joined(separator: ", "))
        .accessibilityValue(done ? "Bought" : "")
        .accessibilityAddTraits(.isButton)
    }
}
