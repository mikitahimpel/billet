import OurioShared
import SwiftUI
import Design

/// Adds a country, searched in the phone's language and in English, or a city or place, then its country.
struct AddPlaceSheet: View {
    let state: HomeState
    let listID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// The place being added, while its country is picked.
    @State private var place: String?
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var list: UsList? { state.us.list(listID) }

    var body: some View {
        BilletSheet(place.map { "Where is “\($0)”?" } ?? "Add a place", scrolls: false) {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                let found = Country.search(trimmed)
                if !found.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(found.prefix(30).enumerated()), id: \.element) { index, code in
                            if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 62) }
                            countryRow(code)
                        }
                    }
                    .cardSurface()
                } else if !trimmed.isEmpty, place != nil {
                    Text("No country by that name.")
                        .font(.ourioCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.l)
                }
                if place == nil {
                    if !trimmed.isEmpty { addAsPlace }
                    if trimmed.isEmpty { popular }
                }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.m)
            .padding(.bottom, Space.xl + Space.s)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .scrollHeader {
            VStack(spacing: 0) {
                if place != nil {
                    SheetSubtitle(text: "Pick its country")
                        .padding(.horizontal, Space.gutter)
                }

                HStack(spacing: Space.s) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Ink.textSecondary)
                    TextField("", text: $query,
                              prompt: Text(place == nil ? "Search countries" : "Search its country")
                                  .foregroundStyle(Ink.textTertiary))
                        .font(.ourioBody)
                        .foregroundStyle(Ink.text)
                        .focused($focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                }
                .fieldSurface()
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.l)
            }
        }
        .toolbar {
            if place != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Back")
                }
            }
        }
        }
        .onAppear { focused = true }
    }

    private func onList(_ code: String) -> Bool {
        list?.items.contains { $0.isCountry && $0.country == code } ?? false
    }

    private func status(_ code: String) -> String {
        let region = Country.region(code)?.title ?? ""
        guard let list, onList(code) else { return region }
        return region + (list.beenCountries.contains(code) ? " · You've been" : " · On your list")
    }

    private func countryRow(_ code: String) -> some View {
        // A place may go in a country already on the list; a country itself only once.
        let added = place == nil && onList(code)
        return Button { pick(code) } label: {
            HStack(spacing: Space.m) {
                CountryFlag(code: code, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Country.name(code))
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                    Text(status(code))
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: Space.s)
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(added ? Ink.accentText : Ink.heroInk)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(added ? AnyShapeStyle(Ink.surfaceRaised) : AnyShapeStyle(.honeyGradient)))
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(RowButtonStyle())
        .disabled(added)
        .accessibilityLabel(Country.name(code))
        .accessibilityHint(added ? "Already on the list" : "Adds it to the list")
    }

    private var addAsPlace: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Or a city or place")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
                .padding(.top, Space.s)
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    place = trimmed
                    query = ""
                }
            } label: {
                HStack(spacing: Space.m) {
                    UsIcon(glyph: UsGlyph(symbol: "mappin", tint: .sky), size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add “\(trimmed)” as a place")
                            .font(.ourioHeadline)
                            .foregroundStyle(Ink.text)
                            .lineLimit(2)
                        Text("Then pick its country")
                            .font(.ourioCaption)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.m)
                .frame(minHeight: 64)
                .contentShape(.rect)
                .cardSurface()
            }
            .buttonStyle(PressScaleStyle())
        }
    }

    private var popular: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Popular with couples")
                .font(.ourioHeadline)
                .foregroundStyle(Ink.textSecondary)
            FlowRow(spacing: Space.s) {
                ForEach(PopularPlace.all, id: \.self) { popular in
                    let added = popular.place == nil && onList(popular.country)
                    Button { add(popular) } label: {
                        HStack(spacing: Space.s) {
                            CountryFlag(code: popular.country, size: 20)
                            Text(popular.place ?? Country.name(popular.country))
                                .font(.ourioCallout)
                                .foregroundStyle(Ink.text)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, Space.m)
                        .frame(minHeight: 34)
                        .background(Ink.surfaceRaised, in: .capsule)
                        .opacity(added ? 0.45 : 1)
                    }
                    .buttonStyle(PressScaleStyle())
                    .disabled(added)
                }
            }
        }
        .padding(.top, Space.s)
    }

    private func back() {
        withAnimation(.snappy(duration: 0.25)) {
            query = place ?? ""
            place = nil
        }
    }

    private func pick(_ code: String) {
        state.us.addTravel(country: code, place: place, to: listID, author: state.viewer)
        dismiss()
    }

    private func add(_ popular: PopularPlace) {
        state.us.addTravel(country: popular.country, place: popular.place, to: listID, author: state.viewer)
        dismiss()
    }
}

struct BeenSheet: View {
    let state: HomeState
    let listID: UUID
    let item: ListItem

    @Environment(\.dismiss) private var dismiss
    @State private var month: TravelMonth?
    @State private var moments: [UUID]
    @State private var picking = false

    init(state: HomeState, listID: UUID, item: ListItem) {
        self.state = state
        self.listID = listID
        self.item = item
        _month = State(initialValue: item.done == nil ? TravelMonth(.now) : item.visitedIn.flatMap(TravelMonth.init))
        _moments = State(initialValue: item.moments)
    }

    private var been: Bool { item.done != nil }
    private var name: String { item.isCountry ? Country.name(item.country ?? "") : item.text }

    var body: some View {
        BilletSheet("Been there", size: .mediumLarge, onConfirm: { save() }) {
                VStack(spacing: Space.l) {
                    VStack(spacing: Space.s) {
                        if item.isCountry, let code = item.country {
                            CountryFlag(code: code, size: 84)
                        } else {
                            UsIcon(glyph: UsGlyph(symbol: "mappin", tint: .sky), size: 84)
                        }
                        Text("\(name), been there!")
                            .font(.ourioTitle)
                            .foregroundStyle(Ink.text)
                            .multilineTextAlignment(.center)
                            .padding(.top, Space.s)
                        subtitle
                    }

                    MonthField(month: $month)
                    photos
                    if been {
                        Button("Not been yet", role: .destructive) { unmark() }
                            .font(.ourioCallout.weight(.semibold))
                            .frame(minHeight: Size.control)
                    }
                }
        }
        .sheet(isPresented: $picking) {
            MomentsPicker(moments: state.moments, selection: $moments)
        }
    }

    /// "Your 8th country together · +5 coins" the first time; the coins are what a tick on any list earns.
    @ViewBuilder
    private var subtitle: some View {
        let countries = state.us.list(listID)?.beenCountries ?? []
        let ordinal = NumberFormatter.localizedString(
            from: NSNumber(value: countries.union([item.country ?? ""]).count), number: .ordinal)
        HStack(spacing: Space.xs) {
            if item.isCountry, !been, let code = item.country, !countries.contains(code) {
                Text("Your \(ordinal) country together ·")
                Text("+5 coins").foregroundStyle(Color.honey)
            } else if !been {
                Text("+5 coins").foregroundStyle(Color.honey)
            } else if let done = item.done {
                Text("Ticked \(done.formatted(.dateTime.day().month().year()))")
            }
        }
        .font(.ourioCallout)
        .foregroundStyle(Ink.textSecondary)
    }

    private var photos: some View {
        Button { picking = true } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(Color.honey)
                    Text(moments.isEmpty ? "Add photos from Moments" : "Photos from Moments")
                        .font(.ourioBody)
                        .foregroundStyle(moments.isEmpty ? Ink.textSecondary : Ink.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.ourioCaption.weight(.bold))
                        .foregroundStyle(Ink.textTertiary)
                }
                if !moments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Space.s) {
                            ForEach(moments, id: \.self) { id in
                                MomentThumb(moments: state.moments, id: id, size: 64)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, CardMetrics.padding)
            .padding(.vertical, Space.m)
            .frame(minHeight: 50)
            .cardSurface()
            .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
    }

    private func save() {
        state.us.markBeen(item.id, in: listID, month: month, moments: moments, by: state.viewer)
        dismiss()
    }

    private func unmark() {
        state.us.setItem(item.id, in: listID, done: false, by: state.viewer)
        dismiss()
    }
}

private struct MonthField: View {
    @Binding var month: TravelMonth?

    private static let years = Array((1960...TravelMonth(.now).year).reversed())

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "calendar")
                .foregroundStyle(Color.honey)
            if let month {
                let monthOfYear = Binding { month.month } set: { self.month = TravelMonth(year: month.year, month: $0) }
                let year = Binding { month.year } set: { self.month = TravelMonth(year: $0, month: month.month) }
                Picker("Month", selection: monthOfYear) {
                    ForEach(1...12, id: \.self) { value in
                        Text(Calendar.current.standaloneMonthSymbols[value - 1]).tag(value)
                    }
                }
                .fixedSize()
                Picker("Year", selection: year) {
                    ForEach(Self.years, id: \.self) { Text(String($0)).tag($0) }
                }
                .fixedSize()
                Spacer(minLength: 0)
                Button { self.month = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Ink.textTertiary)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Leave out when")
            } else {
                Button { month = TravelMonth(.now) } label: {
                    HStack {
                        Text("When did you go?")
                            .font(.ourioBody)
                            .foregroundStyle(Ink.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .pickerStyle(.menu)
        .tint(Ink.text)
        .fieldSurface()
    }
}

/// Picks up to 10 of the pair's moments, the newest first.
private struct MomentsPicker: View {
    let moments: MomentStore
    @Binding var selection: [UUID]

    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 3)
    private static let limit = 10

    var body: some View {
        BilletSheet("Photos from Moments", subtitle: "\(selection.count) of \(Self.limit)", scrolls: false,
                    onConfirm: { dismiss() }) {
        VStack(spacing: 0) {
            if moments.moments.isEmpty {
                EmptyState(icon: UsGlyph(symbol: "photo.fill", tint: .lilac), title: "No moments yet",
                           text: "Photos you share in Moments can go with a trip.")
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Space.xs) {
                        ForEach(moments.moments) { moment in
                            let picked = selection.contains(moment.id)
                            Button { toggle(moment.id) } label: {
                                Color.clear
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay { MomentThumb(moments: moments, id: moment.id, size: nil) }
                                    .corners(.inner)
                                    .overlay(alignment: .topTrailing) {
                                        UsCheck(done: picked)
                                            .background(Circle().fill(.black.opacity(picked ? 0 : 0.25)))
                                            .padding(Space.s)
                                    }
                            }
                            .buttonStyle(PressScaleStyle())
                            .disabled(!picked && selection.count >= Self.limit)
                            .accessibilityLabel(moment.caption.isEmpty ? "Photo" : moment.caption)
                            .accessibilityAddTraits(picked ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.xl + Space.s)
                }
                .softScrollEdges()
            }
        }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selection.firstIndex(of: id) {
            selection.remove(at: index)
        } else if selection.count < Self.limit {
            selection.append(id)
        }
    }
}

/// One moment's photo, square; a moment no longer on this phone shows as an empty tile.
private struct MomentThumb: View {
    let moments: MomentStore
    let id: UUID
    /// Nil fills what it is given.
    let size: CGFloat?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Ink.surfaceRaised
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size == nil ? 0 : Radius.inner, style: .continuous))
        .task(id: id) {
            guard let moment = moments.moments.first(where: { $0.id == id }) else { return }
            image = await moments.thumbnail(for: moment, maxPixels: 256)
        }
        .accessibilityHidden(true)
    }
}
