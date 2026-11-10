import Design
import OurioShared
import SwiftUI

struct ListCard: View {
    let list: UsList
    let state: HomeState

    private var partnerName: String { state.profile.name(of: state.otherPartner) }
    private var empty: Bool { list.items.isEmpty }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.m) {
                CardHeader(list.title) {
                    UsIcon(glyph: list.icon, size: Size.cardMark)
                } detail: {
                    caption.lineLimit(2)
                } trailing: {
                    if !empty { RowChevron() }
                }
                preview
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var preview: some View {
        switch list.kind {
        case .groceries: GroceryPeek(list: list, history: state.us.groceries)
        case .watch: PosterPeek(list: list, partners: state.profile.couple.partners)
        case .travel: FlagPeek(list: list)
        case .food, .books, .bucket, .custom: EmptyView()
        }
    }

    private var caption: Text {
        if empty { return Text(purpose) }
        let change = changeText.map { " · \($0)" } ?? ""
        switch list.kind {
        case .groceries:
            return Text("\(list.open.count) to buy\(change)")
        case .watch:
            let both = list.open.count { Set(state.profile.couple.partners).isSubset(of: $0.wants) }
            guard both > 0 else { return Text("\(list.open.count) to watch\(change)") }
            let wanted = Text("♥ \(both) you both want").foregroundStyle(Color.honey)
            return Text("\(list.open.count) · \(wanted)\(change)")
        case .travel:
            return Text("Been to \(list.travelSummary.been) of \(Country.count) together\(change)")
        case .food, .books, .bucket, .custom:
            return Text("\(list.open.count)\(change)")
        }
    }

    private var purpose: String {
        switch list.kind {
        case .groceries: "Add what you need, \(partnerName) sees it at the store"
        case .watch: "Add movies, then swipe to pick one tonight"
        case .travel: "Countries you dream of and ones you've seen"
        case .food, .books, .bucket, .custom: ListRow.purpose(of: list.kind)
        }
    }

    /// "Masha added 2 today".
    private var changeText: String? {
        guard let change = list.latestChange(by: state.otherPartner) else { return nil }
        let verb: String
        switch change.kind {
        case .added: verb = "added"
        case .done:
            switch list.kind {
            case .groceries: verb = "bought"
            case .watch: verb = "watched"
            case .travel, .food, .books, .bucket, .custom: verb = "ticked off"
            }
        }
        let calendar = Calendar.current
        let day = calendar.isDateInToday(change.at) ? "today"
            : calendar.isDateInYesterday(change.at) ? "yesterday"
            : "on \(change.at.formatted(.dateTime.month(.abbreviated).day()))"
        return "\(partnerName) \(verb) \(change.count) \(day)"
    }
}

private struct GroceryPeek: View {
    let list: UsList
    let history: GroceryHistory

    private static let shown = 5
    private static let samples = ["Bread", "Eggs", "Bananas"]
    private let catalog = GroceryCatalog.bundled

    var body: some View {
        let open = list.open.sorted { $0.added > $1.added }
        WrapLayout(spacing: Space.s) {
            if open.isEmpty {
                ForEach(Self.samples, id: \.self) { chip($0, icon: catalog.aisle(for: $0).icon) }
                more("+")
            } else {
                ForEach(open.prefix(Self.shown)) { chip($0.text, icon: catalog.aisle(for: $0, history: history).icon) }
                if open.count > Self.shown { more("+\(open.count - Self.shown)") }
            }
        }
        .opacity(open.isEmpty ? 0.5 : 1)
        .accessibilityHidden(open.isEmpty)
    }

    private func chip(_ text: String, icon: UsGlyph) -> some View {
        HStack(spacing: Space.s) {
            UsIcon(glyph: icon, size: 22)
            Text(text)
                .font(.ourioCallout)
                .foregroundStyle(Ink.text)
                .lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, Space.m)
        .frame(minHeight: 32)
        .background(Ink.surfaceRaised, in: .capsule)
    }

    private func more(_ text: String) -> some View {
        Text(text)
            .font(.ourioCallout.weight(.semibold))
            .foregroundStyle(Ink.textSecondary)
            .padding(.horizontal, Space.m)
            .frame(minHeight: 32)
            .background(Ink.text.opacity(0.06), in: .capsule)
    }
}

/// Each loads the same TMDB size as the list's grid, so the image cache serves both.
private struct PosterPeek: View {
    let list: UsList
    let partners: [String]

    var body: some View {
        let open = Array(list.open.sorted { $0.added > $1.added }.prefix(6))
        HStack(spacing: Space.s) {
            if open.isEmpty {
                ForEach(["Dune", "Up", "Her", "Big"], id: \.self) { poster(path: nil, title: $0, both: false) }
                    .opacity(0.35)
            } else {
                ForEach(open) { item in
                    poster(path: item.media?.posterPath, title: item.text,
                           both: Set(partners).isSubset(of: item.wants))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func poster(path: String?, title: String, both: Bool) -> some View {
        PosterImage(path: path, title: title, size: .grid, showsTitle: false)
            .frame(width: 46, height: 69)
            .clipShape(.rect(cornerRadius: Radius.inner, style: .continuous))
            .overlay(alignment: .topLeading) {
                if both {
                    Text("♥")
                        .ourioScaledFont(size: 10, weight: .bold, design: .rounded, relativeTo: .caption2)
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, Space.xs)
                        .padding(.vertical, 1)
                        .background(Color.honey, in: .capsule)
                        .padding(Space.xs)
                }
            }
            // Cast by a shape the poster's size, not traced from the poster's pixels: an offscreen pass per poster.
            .background {
                RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                    .fill(Ink.surfaceRaised)
                    .perfShadow(color: .black.opacity(0.3), radius: 4, y: 3)
            }
    }
}

private struct FlagPeek: View {
    let list: UsList

    var body: some View {
        let rows = PlaceRow.rows(of: list)
        let codes = (rows.been + rows.want).compactMap { $0.item.isCountry ? $0.item.country : nil }
        HStack(spacing: Space.m) {
            if codes.isEmpty {
                flags(["IT", "JP", "FR"]).opacity(0.45)
            } else {
                flags(Array(codes.prefix(5)))
                let summary = list.travelSummary
                Capsule()
                    .fill(Ink.text.opacity(0.1))
                    .frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.honeyGradient)
                                .frame(width: max(6, proxy.size.width * Double(summary.been) / Double(Country.count)))
                        }
                    }
                    .clipShape(.capsule)
                Text("\(summary.percent)%")
                    .font(.ourioMicro.monospacedDigit())
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .accessibilityHidden(true)
    }

    private func flags(_ codes: [String]) -> some View {
        HStack(spacing: -8) {
            ForEach(codes, id: \.self) { code in
                CountryFlag(code: code, size: 30)
                    .overlay(Circle().strokeBorder(Ink.surface, lineWidth: 2))
            }
        }
    }
}

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

struct StartListCard: View {
    var body: some View {
        CardHeader("Start a list together") {
            UsIcon(glyph: .init(symbol: "pawprint.fill", tint: .honey), size: Size.cardMark)
        } detail: {
            Text("Gifts, recipes, a trip packing list…")
        } trailing: {
            Image(systemName: "plus")
                .font(.body.weight(.bold))
                .foregroundStyle(Ink.heroInk)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.honeyGradient))
        }
        .padding(CardMetrics.padding)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Ink.text.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
