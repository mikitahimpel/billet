import SwiftUI
import Design
import Transport
import Wire

/// Adds a film or show: TMDB is searched as the partner types, and what it can't find goes in as plain text.
struct AddTitleSheet: View {
    let state: HomeState
    let listID: UUID

    @Environment(ServerSession.self) private var session: ServerSession?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var search = Search.idle
    @FocusState private var focused: Bool

    /// TMDB's answer for the text typed. A failure shows as one, never as the last query's results.
    private enum Search: Equatable {
        case idle
        /// `shown` stays on screen until the answer comes.
        case searching(shown: [TitleSummary])
        case found([TitleSummary])
        case failed
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var results: [TitleSummary] {
        switch search {
        case .searching(let shown): shown
        case .found(let found): found
        case .idle, .failed: []
        }
    }

    var body: some View {
        BilletSheet("Add to watch", scrolls: false) {
        VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Ink.textSecondary)
                TextField("", text: $query, prompt: Text("Search movies and shows").foregroundStyle(Ink.textTertiary))
                    .font(.nookiBody)
                    .foregroundStyle(Ink.text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if case .searching = search { ProgressView() }
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 50)
            .cardSurface(radius: Radius.control)
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
                        .cardSurface()
                    } else if search == .failed {
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
        }
        .onAppear { focused = true }
        .task(id: trimmed) { await find(trimmed) }
    }

    private func find(_ text: String) async {
        guard let source = session?.titles, !text.isEmpty else {
            search = .idle
            return
        }
        // Waits for a pause in the typing; a new letter cancels this task.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        // A cancelled search leaves the state to the one that replaced it.
        search = .searching(shown: results)
        do throws(TransportError) {
            let found = try await source.search(text)
            guard !Task.isCancelled else { return }
            search = .found(found)
        } catch {
            guard !Task.isCancelled else { return }
            search = .failed
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
            .cardSurface()
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
