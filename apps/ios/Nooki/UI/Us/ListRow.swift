import Design
import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UsInterface

struct ListRow: View {
    let list: UsList

    var body: some View {
        Row(list.title, symbol: list.icon.symbol, tint: list.icon.tint.color) {
            Text(counts)
                .font(.ourioBody.monospacedDigit())
                .foregroundStyle(Ink.textSecondary)
            RowChevron()
        }
    }

    private var counts: String {
        let open = list.open.count, done = list.finished.count
        if list.kind.isChecklist || done == 0 { return "\(open)" }
        return "\(open) · \(done) ✓"
    }
}
