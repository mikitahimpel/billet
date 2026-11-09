import OurioShared
import SwiftUI
import Design
import Wire

struct GroceryItemSheet: View {
    let state: HomeState
    let listID: UUID
    let item: ListItem

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    /// Nil until a partner picks one here.
    @State private var aisle: GroceryAisle?
    @State private var deleted = false

    init(state: HomeState, listID: UUID, item: ListItem) {
        self.state = state
        self.listID = listID
        self.item = item
        _amount = State(initialValue: Self.amount(item.quantity, item.note))
    }

    var body: some View {
        let current = aisle ?? GroceryCatalog.bundled.aisle(for: item, history: state.us.groceries)
        BilletSheet("Item", size: .fit) {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                UsIcon(glyph: current.icon, size: 50)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text)
                        .font(.ourioTitle)
                        .foregroundStyle(Ink.text)
                    Text(added)
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }

            UsField(placeholder: "Quantity or note", text: $amount)
                .padding(.top, 18)

            GrocerySectionLabel(title: "Aisle")
            WrapLayout(spacing: 8) {
                ForEach(GroceryAisle.allCases) { choice in
                    FilterChip(choice.title, isSelected: choice == current) { aisle = choice }
                }
            }

            Button(role: .destructive) {
                deleted = true
                withAnimation(.snappy(duration: 0.25)) { state.us.deleteItem(item.id, in: listID) }
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .font(.ourioCallout.weight(.semibold))
            .foregroundStyle(Color.red.opacity(0.85))
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.xl)
        }
        }
        .onDisappear(perform: save)
    }

    private var added: String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(item.added) ? "today"
            : calendar.isDateInYesterday(item.added) ? "yesterday"
            : item.added.formatted(.dateTime.day().month())
        guard !item.author.isEmpty else { return "Added \(day)" }
        return "Added by \(state.profile.name(of: item.author)) · \(day)"
    }

    private func save() {
        guard !deleted else { return }
        let (quantity, note) = Self.split(amount)
        var details = item.details
        details.quantity = quantity
        details.note = note
        details.aisle = aisle?.rawValue ?? item.aisle
        state.us.editItem(item.id, in: listID, details: details)
    }

    /// "2, for tea": a leading amount up to the first comma is the quantity, the rest is the note.
    static func split(_ text: String) -> (quantity: String?, note: String?) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = text.first else { return (nil, nil) }
        guard first.isNumber else { return (nil, String(text.prefix(500))) }
        let parts = text.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let note = parts.count > 1 && !parts[1].isEmpty ? String(parts[1].prefix(500)) : nil
        return (String(parts[0].prefix(40)), note)
    }

    static func amount(_ quantity: String?, _ note: String?) -> String {
        [quantity, note].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
