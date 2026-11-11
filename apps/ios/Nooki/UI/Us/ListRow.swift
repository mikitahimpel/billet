import Design
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UsInterface

struct ListRow: View {
    let list: UsList

    static func purpose(of kind: ListKind) -> String {
        switch kind {
        case .food: "Restaurants and cafés to try together"
        case .books: "Books you both want to read"
        case .bucket: "Things to do together one day"
        case .groceries: "Things to buy"
        case .watch: "Movies and shows to watch together"
        case .travel: "Places you want to go"
        case .custom: "Add the first thing together"
        }
    }

    var body: some View {
        Row(list.title, detail: list.items.isEmpty ? Self.purpose(of: list.kind) : nil,
            symbol: list.icon.symbol, tint: list.icon.tint.color) {
            if !list.items.isEmpty {
                Text(counts)
                    .font(.ourioCaption.monospacedDigit())
                    .foregroundStyle(Ink.textSecondary)
            }
            RowChevron()
        }
    }

    private var counts: String {
        let open = list.open.count, done = list.finished.count
        if list.kind.isChecklist || done == 0 { return "\(open)" }
        return "\(open) · \(done) ✓"
    }
}
