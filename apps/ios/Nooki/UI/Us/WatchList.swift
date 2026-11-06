import SwiftUI
import Transport
import Wire

/// The card details this list has fetched, by title, so the service filters and every reopened card need no second
/// request.
@MainActor
@Observable
final class WatchDetails {
    private(set) var byTitle: [String: TitleDetails] = [:]
    @ObservationIgnored private var asked: Set<String> = []

    static func key(_ media: ItemMedia) -> String { "\(media.kind.rawValue)/\(media.tmdb)" }

    func details(of media: ItemMedia) -> TitleDetails? { byTitle[Self.key(media)] }

    /// Fetches each title not asked for yet, one at a time. A failure is left for the card to ask again.
    func load(_ media: [ItemMedia], from source: TitleSource) async {
        for media in media where !asked.contains(Self.key(media)) {
            asked.insert(Self.key(media))
            if let details = try? await source.details(media.wireKind, media.tmdb) {
                byTitle[Self.key(media)] = details
            }
        }
    }

    func store(_ details: TitleDetails, for media: ItemMedia) {
        asked.insert(Self.key(media))
        byTitle[Self.key(media)] = details
    }
}

enum WatchFilter: Hashable {
    case all, both, movies, shows
    /// A streaming service, by its TMDB provider id.
    case service(Int)
}

/// The To watch list: posters three to a row, the ones both partners want marked, and what was watched together
/// folded away below.
struct WatchListBody: View {
    let state: HomeState
    let list: UsList
    let details: WatchDetails
    var open: (ListItem) -> Void

    @Environment(ServerSession.self) private var session: ServerSession?
    @State private var filter = WatchFilter.all
    @State private var showsWatched = false
    @State private var picking = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if list.items.isEmpty {
                UsEmpty(icon: list.icon, title: "Nothing to watch yet",
                        text: "Add a film or a show with +. You both see this list.")
            } else {
                if canPick {
                    UsPrimaryButton(title: "🍿 Pick tonight") { picking = true }
                }
                filters
                let shown = list.open.filter(passes)
                if shown.isEmpty {
                    Text("Nothing here for this filter.")
                        .font(.nookiCallout)
                        .foregroundStyle(Ink.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.xl)
                } else {
                    grid(shown, watched: false)
                }
                watchedSection
            }
        }
        .task(id: list.items.compactMap(\.media).map(WatchDetails.key)) {
            guard let source = session?.titles else { return }
            await details.load(list.open.compactMap(\.media), from: source)
        }
        .fullScreenCover(isPresented: $picking) {
            PickTonightScreen(state: state, list: list, details: details)
        }
    }

    /// Pick tonight is the pair's, so it needs the partner, and the server can switch it off.
    private var canPick: Bool {
        !list.open.isEmpty && session?.pickTonight != nil && PickTonightModel.isOn(state.rooms.remote)
    }

    private func bothWant(_ item: ListItem) -> Bool {
        Set(state.profile.couple.partners).isSubset(of: item.wants)
    }

    private func passes(_ item: ListItem) -> Bool {
        switch filter {
        case .all: true
        case .both: bothWant(item)
        case .movies: item.media?.kind == .movie
        case .shows: item.media?.kind == .tv
        case .service(let id): item.media.flatMap(details.details)?.watch.stream.contains { $0.id == id } ?? false
        }
    }

    /// The services that stream any title still to watch, the most titles first.
    private var services: [WatchProvider] {
        var counts: [Int: (provider: WatchProvider, titles: Int)] = [:]
        for media in list.open.compactMap(\.media) {
            for provider in details.details(of: media)?.watch.stream ?? [] {
                counts[provider.id, default: (provider, 0)].titles += 1
            }
        }
        return counts.values.sorted { ($0.titles, $1.provider.name) > ($1.titles, $0.provider.name) }.map(\.provider)
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Space.s) {
                chip("All", .all)
                chip("♥ Both want", .both)
                chip("Movies", .movies)
                chip("Shows", .shows)
                ForEach(services, id: \.id) { chip($0.name, .service($0.id)) }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(_ title: String, _ value: WatchFilter) -> some View {
        UsChip(title: title, selected: filter == value) {
            withAnimation(.snappy(duration: 0.2)) { filter = value }
        }
    }

    private func grid(_ items: [ListItem], watched: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            ForEach(items) { item in
                Button { open(item) } label: {
                    PosterTile(item: item, both: bothWant(item), profile: state.profile)
                        .opacity(watched ? 0.6 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var watchedSection: some View {
        let watched = list.finished
        if !watched.isEmpty {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsWatched.toggle() }
            } label: {
                HStack(spacing: Space.m) {
                    UsIcon(glyph: UsGlyph(symbol: "checkmark", tint: .coral), size: 34)
                    Text("Watched together")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: Space.s)
                    Text("\(watched.count)")
                        .font(.nookiCallout.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textTertiary)
                        .rotationEffect(.degrees(showsWatched ? 90 : 0))
                }
                .padding(.horizontal, Space.m)
                .frame(minHeight: 56)
                .contentShape(.rect)
                .usCard()
            }
            .buttonStyle(.plain)
            if showsWatched { grid(watched, watched: true) }
        }
    }
}

/// One poster: TMDB's when the title has one, else its name on a warm card. Marked "♥ both" when both partners
/// want it, else with the monogram of who added it.
struct PosterTile: View {
    let item: ListItem
    let both: Bool
    let profile: CoupleStore

    var body: some View {
        PosterImage(path: item.media?.posterPath, title: item.text, size: .grid)
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
            .overlay(alignment: .topLeading) {
                Group {
                    if both {
                        Text("♥ both")
                            .font(.nookiMicro)
                            .foregroundStyle(Ink.heroInk)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.honey, in: .capsule)
                    } else {
                        Monogram(partner: item.author, profile: profile, size: 22)
                    }
                }
                .padding(6)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(both ? "\(item.text), you both want it" : item.text)
            .accessibilityAddTraits(.isButton)
    }
}

/// A TMDB image over a warm placeholder that names the title, so a missing or slow poster still reads.
struct PosterImage: View {
    let path: String?
    let title: String
    let size: TmdbImage.Size
    var showsTitle = true

    var body: some View {
        LinearGradient(colors: Self.colors(title), startPoint: .top, endPoint: .bottom)
            .overlay(alignment: .bottomLeading) {
                if showsTitle {
                    Text(title)
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(Space.s)
                }
            }
            .overlay {
                if let url = TmdbImage.url(path, size) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        phase.image?.resizable().scaledToFill()
                    }
                }
            }
            .clipped()
    }

    /// One of a few warm pairs, the same for a title every time.
    private static func colors(_ title: String) -> [Color] {
        let pairs: [(UInt32, UInt32)] = [(0x6E4630, 0x2A1A12), (0x3C4778, 0x2A1A12), (0x7A3B47, 0x2A1A12),
                                         (0x4E6B4A, 0x2A1A12), (0x8A5A2B, 0x2A1A12)]
        let pair = pairs[Int(title.unicodeScalars.reduce(0) { $0 &+ $1.value } % UInt32(pairs.count))]
        return [Color(hex: pair.0), Color(hex: pair.1)]
    }
}

/// "2016 · Movie · 1 h 56 min · ★ 7.6", leaving out what TMDB doesn't know.
enum TitleCaption {
    static func of(_ title: TitleSummary, genre: String? = nil) -> String {
        var parts: [String] = []
        if let year = title.year { parts.append(String(year)) }
        if let genre { parts.append(genre) } else { parts.append(kind(title.kind)) }
        if let runtime = title.runtime { parts.append(minutes(runtime)) }
        if let seasons = title.seasons { parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons") }
        if let rating = title.rating { parts.append("★ \(rating.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }

    static func kind(_ kind: ListMediaKind) -> String {
        switch kind {
        case .movie: "Movie"
        case .tv: "Show"
        }
    }

    static func minutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}

/// Adds a film or show: TMDB is searched as the partner types, and what it can't find goes in as plain text.
struct AddTitleSheet: View {
    let state: HomeState
    let listID: UUID

    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [TitleSummary] = []
    @State private var searching = false
    @State private var failed = false
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: "Add to watch") {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Ink.surfaceRaised))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ink.textSecondary)
                TextField("", text: $query, prompt: Text("Search movies and shows").foregroundStyle(Ink.textTertiary))
                    .font(.nookiBody)
                    .foregroundStyle(Ink.text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if searching { ProgressView() }
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 50)
            .usCard(radius: Radius.control)
            .padding(.horizontal, Space.gutter)
            .padding(.top, 14)

            ScrollView {
                VStack(spacing: Space.m) {
                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element) { index, title in
                                if index > 0 { Divider().overlay(Ink.separator).padding(.leading, 70) }
                                resultRow(title)
                            }
                        }
                        .usCard()
                    } else if failed {
                        note("Search isn't reachable right now. You can still add it as text.")
                    } else if session?.titles == nil {
                        note("Search needs the server. You can still add it as text.")
                    }
                    if !trimmed.isEmpty { addAsText }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.m)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .usSheet()
        .onAppear { focused = true }
        .task(id: trimmed) { await search(trimmed) }
    }

    private func search(_ text: String) async {
        guard let source = session?.titles, !text.isEmpty else {
            results = []
            failed = false
            return
        }
        // Waits for a pause in the typing; a new letter cancels this task.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do throws(TransportError) {
            let found = try await source.search(text)
            guard !Task.isCancelled else { return }
            results = found
            failed = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }

    private func added(_ title: TitleSummary) -> Bool {
        state.us.list(listID)?.items.contains { $0.media?.tmdb == title.tmdb && $0.media?.wireKind == title.kind }
            ?? false
    }

    private func resultRow(_ title: TitleSummary) -> some View {
        let isAdded = added(title)
        return Button { add(title) } label: {
            HStack(spacing: Space.m) {
                PosterImage(path: title.posterPath, title: title.title, size: .small, showsTitle: false)
                    .frame(width: 44, height: 64)
                    .clipShape(.rect(cornerRadius: Radius.tag, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.title)
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(2)
                    Text(TitleCaption.of(title))
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: Space.s)
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.body.weight(.bold))
                    .foregroundStyle(isAdded ? Ink.accentText : Ink.heroInk)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isAdded ? AnyShapeStyle(Ink.surfaceRaised) : AnyShapeStyle(.honeyGradient)))
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 84)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityLabel("\(title.title), \(TitleCaption.of(title))")
        .accessibilityHint(isAdded ? "Already on the list" : "Adds it to the list")
    }

    private var addAsText: some View {
        Button { addText() } label: {
            HStack(spacing: Space.m) {
                UsIcon(glyph: UsGlyph(symbol: "pencil", tint: .coral), size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add “\(trimmed)” as text")
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .lineLimit(2)
                    Text("No poster or details")
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(minHeight: 64)
            .contentShape(.rect)
            .usCard()
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.nookiCallout)
            .foregroundStyle(Ink.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
    }

    private func add(_ title: TitleSummary) {
        let kind: ItemMedia.Kind = switch title.kind {
        case .movie: .movie
        case .tv: .tv
        }
        state.us.addItem(title.title, to: listID, author: state.viewer,
                         media: ItemMedia(kind: kind, tmdb: title.tmdb, year: title.year, posterPath: title.posterPath))
        dismiss()
    }

    private func addText() {
        state.us.addItem(trimmed, to: listID, author: state.viewer)
        dismiss()
    }
}

/// One title's card: backdrop and poster, what it is, where to watch it, and whether both partners want it.
struct MovieCard: View {
    let state: HomeState
    let listID: UUID
    let itemID: UUID
    let details: WatchDetails

    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    private var item: ListItem? { state.us.list(listID)?.items.first { $0.id == itemID } }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                UsEmpty(icon: UsGlyph(symbol: "popcorn.fill", tint: .coral), title: "Gone", text: "This title is no longer on the list.")
            }
        }
        .usSheet()
        .task { await load() }
    }

    private func load() async {
        guard let media = item?.media, details.details(of: media) == nil, let source = session?.titles else { return }
        do throws(TransportError) {
            details.store(try await source.details(media.wireKind, media.tmdb), for: media)
        } catch {
            failed = true
        }
    }

    private func content(_ item: ListItem) -> some View {
        let info = item.media.flatMap(details.details)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(item, info: info)
                VStack(alignment: .leading, spacing: Space.l) {
                    if let info {
                        if !info.overview.isEmpty {
                            Text(info.overview)
                                .font(.nookiBody)
                                .foregroundStyle(Ink.textSecondary)
                        }
                        whereToWatch(info.watch)
                    } else if item.media != nil {
                        if failed {
                            Text("The details aren't reachable right now.")
                                .font(.nookiCallout)
                                .foregroundStyle(Ink.textSecondary)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    wants(item)
                    actions(item)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
    }

    private func header(_ item: ListItem, info: TitleDetails?) -> some View {
        let path = item.media?.posterPath ?? info?.summary.posterPath
        return VStack(alignment: .leading, spacing: 0) {
            PosterImage(path: info?.backdropPath ?? path, title: item.text, size: .card, showsTitle: false)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .overlay {
                    LinearGradient(colors: [.clear, Ink.screen.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    PosterImage(path: path, title: item.text, size: .card)
                        .frame(width: 96, height: 142)
                        .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Ink.screen, lineWidth: 3)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .padding(.leading, Space.gutter)
                        .offset(y: 40)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.nookiTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(3)
                if let caption = caption(item, info: info) {
                    Text(caption)
                        .font(.nookiCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            .frame(minHeight: 40, alignment: .top)
            .padding(.leading, 132)
            .padding(.trailing, Space.gutter)
            .padding(.top, 10)
        }
    }

    private func caption(_ item: ListItem, info: TitleDetails?) -> String? {
        if let info { return TitleCaption.of(info.summary, genre: info.genres.first) }
        guard let media = item.media else { return nil }
        return [media.year.map(String.init), TitleCaption.kind(media.wireKind)].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func whereToWatch(_ watch: WatchOptions) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Where to watch")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Spacer()
                Text("JustWatch")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            if watch.stream.isEmpty && watch.rentOrBuy.isEmpty {
                Text("Not streaming in your region yet.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.s) {
                        ForEach(watch.stream, id: \.id) { provider(name: $0.name, extra: nil) }
                        ForEach(watch.rentOrBuy, id: \.id) { provider(name: $0.name, extra: "rent or buy") }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            if let link = watch.link.flatMap(URL.init(string:)) {
                Link("See all options", destination: link)
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
            }
        }
    }

    private func provider(name: String, extra: String?) -> some View {
        HStack(spacing: 4) {
            Text(name)
            if let extra { Text(extra).foregroundStyle(Ink.textTertiary) }
        }
        .font(.nookiCallout)
        .foregroundStyle(Ink.text)
        .padding(.horizontal, 14)
        .frame(minHeight: 34)
        .background(Ink.surfaceRaised, in: .capsule)
    }

    @ViewBuilder
    private func wants(_ item: ListItem) -> some View {
        let couple = state.profile.couple
        let viewerWants = item.wants.contains(state.viewer)
        let partnerWants = item.wants.contains(couple.other)
        HStack(spacing: Space.m) {
            HStack(spacing: -14) {
                ForEach(item.wants.filter(couple.partners.contains), id: \.self) {
                    Monogram(partner: $0, profile: state.profile, size: 34)
                }
            }
            if viewerWants && partnerWants {
                Text("You both want to watch it")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text("♥").foregroundStyle(Color.honey)
            } else if viewerWants {
                Text("Waiting for \(couple.name(of: couple.other))")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
            } else {
                Text(partnerWants ? "\(couple.name(of: couple.other)) wants to watch it" : "Want to watch it?")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Button("Want too") {
                    withAnimation(.snappy(duration: 0.25)) {
                        state.us.setWant(itemID, in: listID, wants: true, by: state.viewer)
                    }
                }
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Ink.heroInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Color.honey, in: .capsule)
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .usCard()
    }

    @ViewBuilder
    private func actions(_ item: ListItem) -> some View {
        if let done = item.done {
            VStack(spacing: Space.s) {
                Label("Watched together on \(done.formatted(.dateTime.day().month()))", systemImage: "checkmark.circle.fill")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Button("Not watched yet") {
                    state.us.setItem(itemID, in: listID, done: false, by: state.viewer)
                }
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Ink.accentText)
            }
            .frame(maxWidth: .infinity)
        } else {
            UsPrimaryButton(title: "Watched together", symbol: "checkmark") {
                state.us.setItem(itemID, in: listID, done: true, by: state.viewer)
                dismiss()
            }
        }
        Button {
            dismiss()
            // The list's sheet gives way to Date night once this card has closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.usRoute = .dates }
        } label: {
            Label("Plan a movie night", systemImage: "dice.fill")
                .font(.nookiHeadline)
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(Ink.surfaceRaised, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
