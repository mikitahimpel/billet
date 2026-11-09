import SwiftUI
import Design
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
                EmptyState(icon: list.icon, title: "Nothing to watch yet",
                           text: "Add a film or a show with +. You both see this list.")
            } else {
                if canPick {
                    PrimaryButton("🍿 Pick tonight") { picking = true }
                }
                filters
                let shown = list.open.filter(passes)
                if shown.isEmpty {
                    Text("Nothing here for this filter.")
                        .font(.ourioCallout)
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
        FilterChip(title, isSelected: filter == value) {
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
                        .font(.ourioHeadline)
                        .foregroundStyle(Ink.text)
                    Spacer(minLength: Space.s)
                    Text("\(watched.count)")
                        .font(.ourioCallout.monospacedDigit())
                        .foregroundStyle(Ink.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textTertiary)
                        .rotationEffect(.degrees(showsWatched ? 90 : 0))
                }
                .padding(.horizontal, Space.m)
                .frame(minHeight: 56)
                .contentShape(.rect)
                .cardSurface()
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
            .clipShape(.rect(cornerRadius: Radius.inner, style: .continuous))
            .overlay(alignment: .topLeading) {
                Group {
                    if both {
                        Text("♥ both")
                            .font(.ourioMicro)
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
                        .font(.ourioCaption.weight(.semibold))
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
