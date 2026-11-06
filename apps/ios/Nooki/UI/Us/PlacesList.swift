import SwiftUI

/// Places to go: how many of the 195 countries the pair has been to, a map of them, and the countries by tab.
/// Places in a country show under it; a place whose country isn't on the list, or a line of text, is its own row.
struct PlacesListBody: View {
    let state: HomeState
    let list: UsList
    /// Opens the "been there" sheet: from a tick still to go, or a row already been to.
    var mark: (ListItem) -> Void

    @State private var tab = PlacesTab.want

    var body: some View {
        let rows = PlaceRow.rows(of: list)
        VStack(alignment: .leading, spacing: Space.m) {
            hero
            HStack(spacing: Space.s) {
                UsChip(title: "Want to go · \(rows.want.count)", selected: tab == .want) { select(.want) }
                UsChip(title: "Been · \(rows.been.count)", selected: tab == .been) { select(.been) }
            }
            .padding(.top, 2)
            let shown = tab == .want ? rows.want : rows.been
            if shown.isEmpty {
                Text(tab == .want ? "Add a country or a place with +." : "Tick a country once you've been together.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.item.id) { index, row in
                        if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 60) }
                        rowView(row)
                    }
                }
                .usCard()
            }
        }
    }

    private func select(_ value: PlacesTab) {
        withAnimation(.snappy(duration: 0.2)) { tab = value }
    }

    private var hero: some View {
        let summary = list.travelSummary
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(summary.been)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.text)
                Text("of \(Country.count) countries together · \(summary.percent)%")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
            .accessibilityElement(children: .combine)
            WorldMapView(been: list.beenCountries, wanted: list.wantedCountries)
            HStack(spacing: Space.l) {
                legend("Been together") { Circle().fill(Color.honey) }
                legend("Want to go") {
                    Circle().strokeBorder(WorldMapView.wantedColor, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                }
            }
        }
        .padding(Space.l)
        .usCard(radius: Radius.hero, warm: true)
    }

    private func legend(_ title: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 6) {
            mark().frame(width: 10, height: 10)
            Text(title)
                .font(.nookiCaption)
                .foregroundStyle(Ink.textSecondary)
        }
    }

    private func rowView(_ row: PlaceRow) -> some View {
        let item = row.item
        let been = item.done != nil
        return HStack(spacing: Space.m) {
            if let code = item.country, Country.isCountry(code) {
                CountryFlag(code: code, size: 36)
            } else {
                UsIcon(glyph: UsGlyph(symbol: "mappin", tint: .sky), size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                if let caption = row.caption {
                    Text(caption)
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.s)
            Monogram(partner: item.author, profile: state.profile, size: 20)
            Button {
                if been {
                    withAnimation(.snappy(duration: 0.25)) {
                        for twin in twins(of: item) {
                            state.us.setItem(twin.id, in: list.id, done: false, by: state.viewer)
                        }
                    }
                } else {
                    mark(item)
                }
            } label: {
                UsCheck(done: been)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(been ? "Mark as not been" : "Mark as been")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .contentShape(.rect)
        .onTapGesture { if been { mark(item) } }
        .contextMenu {
            ForEach(row.places) { place in
                Button(role: .destructive) { delete(place) } label: {
                    Label("Remove \(place.text)", systemImage: "mappin.slash")
                }
            }
            Button(role: .destructive) {
                for each in row.places + twins(of: item) { delete(each) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// The item, with any other item naming the same country.
    private func twins(of item: ListItem) -> [ListItem] {
        item.isCountry ? list.items.filter { $0.isCountry && $0.country == item.country } : [item]
    }

    private func delete(_ item: ListItem) {
        withAnimation(.snappy(duration: 0.25)) { state.us.deleteItem(item.id, in: list.id) }
    }
}

enum PlacesTab { case want, been }

/// One row of Places to go: a country with the places in it, a place on its own, or a line of text.
struct PlaceRow {
    let item: ListItem
    var places: [ListItem] = []

    var title: String {
        item.isCountry ? Country.name(item.country ?? "") : item.text
    }

    /// The places in the country, or the country of a place on its own; for a row been to, when and the photos.
    var caption: String? {
        var parts: [String] = []
        if item.done != nil {
            if let month = item.visitedIn.flatMap(TravelMonth.init) { parts.append(month.formatted()) }
            if !item.moments.isEmpty {
                parts.append(item.moments.count == 1 ? "1 photo" : "\(item.moments.count) photos")
            }
        }
        if item.isCountry {
            if !places.isEmpty { parts.insert(places.map(\.text).joined(separator: ", "), at: 0) }
        } else if let code = item.country, Country.isCountry(code) {
            parts.insert(Country.name(code), at: 0)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The list's rows, the newest first: a country named twice, as when both partners add it at once, shows once,
    /// been to if either was ticked, with the places in it under it.
    static func rows(of list: UsList) -> (want: [PlaceRow], been: [PlaceRow]) {
        let byCountry = Dictionary(grouping: list.items.filter(\.isCountry)) { $0.country ?? "" }
        let countries = byCountry.map { code, items in
            let oldest = items.sorted { $0.added < $1.added }
            let places = list.items.filter { $0.place && $0.country == code }.sorted { $0.added < $1.added }
            return PlaceRow(item: oldest.first { $0.done != nil } ?? oldest[0], places: places)
        }
        let loose = list.items.filter { !$0.isCountry && !($0.place && byCountry[$0.country ?? ""] != nil) }
            .map { PlaceRow(item: $0) }
        let all = (countries + loose).sorted { ($0.item.done ?? $0.item.added) > ($1.item.done ?? $1.item.added) }
        return (all.filter { $0.item.done == nil }, all.filter { $0.item.done != nil })
    }
}
