import OurioShared
import PhotosUI
import SwiftUI
import Design

struct DatePreset: Identifiable {
    let title: String
    let filter: DateFilter

    var id: String { title }

    static let all = [
        DatePreset(title: "Night in", filter: DateFilter(places: [.home], lengths: [.hour, .evening])),
        DatePreset(title: "Free", filter: DateFilter(costs: [.free])),
        DatePreset(title: "Long distance", filter: DateFilter(places: [.apart])),
    ]
}

struct DateFilterSheet: View {
    @Binding var filter: DateFilter
    let count: (DateFilter) -> Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fits = count(filter)
        BilletSheet("Filters", subtitle: fits == 1 ? "1 idea fits" : "\(fits) ideas fit", scrolls: false) {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    group("Quick picks") {
                        HStack(spacing: 8) {
                            ForEach(DatePreset.all) { preset in
                                FilterChip(preset.title, isSelected: filter == preset.filter) {
                                    withAnimation(.snappy(duration: 0.2)) { filter = preset.filter }
                                }
                            }
                        }
                    }
                    group("Where") {
                        options(DateIdea.Place.allCases.map(DateFilter.Tag.place), columns: 2)
                    }
                    group("Budget") {
                        options(DateIdea.Cost.allCases.map(DateFilter.Tag.cost), columns: 3)
                    }
                    group("Time") {
                        options(DateIdea.Length.allCases.map(DateFilter.Tag.length), columns: 3)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .softScrollEdges()
            .scrollIndicators(.hidden)

            PrimaryButton(fits == 0 ? "Nothing fits" : "Show \(fits) ideas") { dismiss() }
                .disabled(fits == 0)
                .opacity(fits == 0 ? 0.5 : 1)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.m)
        }
        .toolbar {
            if !filter.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { withAnimation(.snappy(duration: 0.2)) { filter = DateFilter() } }
                }
            }
        }
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
            content()
        }
    }

    private func options(_ tags: [DateFilter.Tag], columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                option(tag)
            }
        }
    }

    private func option(_ tag: DateFilter.Tag) -> some View {
        let selected = filter.contains(tag)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { filter.toggle(tag) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tag.symbol)
                    .font(.ourioHeadline)
                    .foregroundStyle(selected ? Color.honey : Ink.textSecondary)
                Text(tag.title)
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(selected ? Color.honey.opacity(0.22) : Ink.surface,
                        in: .rect(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .stroke(selected ? Color.honey : Ink.separator, lineWidth: selected ? 1.5 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension DateIdea.Place {
    var title: String {
        switch self {
        case .home: "At home"
        case .city: "In town"
        case .nature: "Outdoors"
        case .apart: "Long distance"
        }
    }
}

extension DateIdea.Cost {
    var title: String {
        switch self {
        case .free: "Free"
        case .cheap: "Cheap"
        case .nice: "Treat"
        }
    }

    var symbol: String {
        switch self {
        case .free: "heart.fill"
        case .cheap: "dollarsign.circle.fill"
        case .nice: "sparkles"
        }
    }
}

extension DateIdea.Length {
    var title: String {
        switch self {
        case .hour: "1 hour"
        case .evening: "Evening"
        case .day: "All day"
        }
    }

    var symbol: String {
        switch self {
        case .hour: "clock.fill"
        case .evening: "moon.stars.fill"
        case .day: "sun.max.fill"
        }
    }
}

extension DateFilter {
    enum Tag: Hashable {
        case place(DateIdea.Place)
        case cost(DateIdea.Cost)
        case length(DateIdea.Length)

        var title: String {
            switch self {
            case .place(let place): place.title
            case .cost(let cost): cost.title
            case .length(let length): length.title
            }
        }

        var symbol: String {
            switch self {
            case .place(let place): place.icon.symbol
            case .cost(let cost): cost.symbol
            case .length(let length): length.symbol
            }
        }
    }

    var isEmpty: Bool { places.isEmpty && costs.isEmpty && lengths.isEmpty }

    /// In the sheet's order, so the chips above the deck don't jump around.
    var tags: [Tag] {
        DateIdea.Place.allCases.filter(places.contains).map(Tag.place)
            + DateIdea.Cost.allCases.filter(costs.contains).map(Tag.cost)
            + DateIdea.Length.allCases.filter(lengths.contains).map(Tag.length)
    }

    func contains(_ tag: Tag) -> Bool {
        switch tag {
        case .place(let place): places.contains(place)
        case .cost(let cost): costs.contains(cost)
        case .length(let length): lengths.contains(length)
        }
    }

    mutating func toggle(_ tag: Tag) {
        switch tag {
        case .place(let place): if places.remove(place) == nil { places.insert(place) }
        case .cost(let cost): if costs.remove(cost) == nil { costs.insert(cost) }
        case .length(let length): if lengths.remove(length) == nil { lengths.insert(length) }
        }
    }
}
