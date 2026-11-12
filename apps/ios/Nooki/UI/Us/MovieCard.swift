import MomentsInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import Design
import Transport
import UsInterface
import Wire

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
        BilletSheet(item?.text ?? "Title", scrolls: false) {
            if let item {
                content(item)
            } else {
                EmptyState(icon: UsGlyph(symbol: "popcorn.fill", tint: .coral), title: "Gone", text: "This title is no longer on the list.")
            }
        }
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
                                .font(.ourioBody)
                                .foregroundStyle(Ink.textSecondary)
                        }
                        whereToWatch(info.watch)
                    } else if item.media != nil {
                        if failed {
                            Text("The details aren't reachable right now.")
                                .font(.ourioCallout)
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
                .padding(.bottom, Space.xl + Space.s)
            }
        }
        .ourioScrollEdges()
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
                        .corners(.inner)
                        .perfShadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .padding(.leading, Space.gutter)
                        .offset(y: 40)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.ourioTitle)
                    .foregroundStyle(Ink.text)
                    .lineLimit(3)
                if let caption = caption(item, info: info) {
                    Text(caption)
                        .font(.ourioCaption)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
            .frame(minHeight: 40, alignment: .top)
            .padding(.leading, 132)
            .padding(.trailing, Space.gutter)
            .padding(.top, Space.m)
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
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Spacer()
                Text("JustWatch")
                    .font(.ourioCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            if watch.stream.isEmpty && watch.rentOrBuy.isEmpty {
                Text("Not streaming in your region yet.")
                    .font(.ourioCallout)
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
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
            }
        }
    }

    private func provider(name: String, extra: String?) -> some View {
        Chip(extra.map { "\(name) · \($0)" } ?? name)
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
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text("♥").foregroundStyle(Color.honey)
            } else if viewerWants {
                Text("Waiting for \(couple.name(of: couple.other))")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
            } else {
                Text(partnerWants ? "\(couple.name(of: couple.other)) wants to watch it" : "Want to watch it?")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                PrimaryButton("Want too", fullWidth: false) {
                    withAnimation(Motion.spring(0.25)) {
                        state.us.setWant(itemID, in: listID, wants: true, by: state.viewer)
                    }
                }
            }
        }
        .padding(CardMetrics.padding)
        .cardSurface()
    }

    @ViewBuilder
    private func actions(_ item: ListItem) -> some View {
        if let done = item.done {
            VStack(spacing: Space.s) {
                Label("Watched together on \(done.formatted(.dateTime.day().month()))", systemImage: "checkmark.circle.fill")
                    .font(.ourioHeadline)
                    .foregroundStyle(Ink.text)
                Button("Not watched yet") {
                    state.us.setItem(itemID, in: listID, done: false, by: state.viewer)
                }
                .font(.ourioCallout.weight(.semibold))
                .foregroundStyle(Ink.accentText)
            }
            .frame(maxWidth: .infinity)
        } else {
            PrimaryButton("Watched together", symbol: "checkmark") {
                state.us.setItem(itemID, in: listID, done: true, by: state.viewer)
                dismiss()
            }
        }
        SecondaryButton("Plan a movie night", symbol: "dice.fill") {
            dismiss()
            // The list's sheet gives way to Date night once this card has closed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { state.usRoute = .dates }
        }
    }
}
