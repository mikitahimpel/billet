import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import UsInterface

struct GrocerySuggestions: View {
    let draft: String
    let list: UsList
    let history: GroceryHistory
    /// The quick picks: while the field is focused, and on an empty list so the first item is one tap.
    var showsOften = true
    var onAdd: (String) -> Void

    private let catalog = GroceryCatalog.bundled

    private static let staples = ["Milk", "Bread", "Eggs", "Bananas", "Coffee", "Pasta", "Tomatoes", "Cheese"]

    var body: some View {
        let onList = Set(list.open.map { GroceryWords.key($0.text) })
        VStack(alignment: .leading, spacing: 0) {
            let suggestions = catalog.suggestions(for: draft, history: history, limit: 4)
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 58) }
                        row(suggestion, onList: onList.contains(suggestion.id))
                    }
                }
                .cardSurface()
            }

            let often = showsOften && draft.isEmpty ? often(excluding: onList) : []
            if !often.isEmpty {
                GrocerySectionLabel(title: history.often(limit: 1).isEmpty ? "Quick add" : "You often buy",
                                    top: suggestions.isEmpty ? 4 : 18)
                FlowRow(spacing: Space.s) {
                    ForEach(often, id: \.self) { text in
                        FilterChip(text, isSelected: false) { onAdd(text) }
                            .accessibilityLabel("Add \(text)")
                    }
                }
            }
        }
    }

    private func row(_ suggestion: GrocerySuggestion, onList: Bool) -> some View {
        Button {
            onAdd(suggestion.text)
        } label: {
            HStack(spacing: Space.m) {
                UsIcon(glyph: suggestion.aisle.icon, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(suggestion.text)
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                    Text(onList ? "Already on the list" : suggestion.aisle.title)
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 8)
                if onList {
                    UsCheck(done: true)
                } else {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Ink.heroInk)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.honeyGradient))
                }
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 56)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
        .disabled(onList)
        .opacity(onList ? 0.55 : 1)
        .accessibilityLabel(onList ? "\(suggestion.text), already on the list" : "Add \(suggestion.text)")
    }

    /// The pair's eight most bought, not on the list now, topped up with staples.
    private func often(excluding onList: Set<String>) -> [String] {
        var seen = onList
        let names = history.often(limit: .max).map(\.text) + Self.staples
        return Array(names.filter { seen.insert(GroceryWords.key($0)).inserted }.prefix(8))
    }
}
