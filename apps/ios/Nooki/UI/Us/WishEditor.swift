import OurioShared
import SwiftUI
import Design

// MARK: - Editor

struct WishEditor: View {
    private enum PictureChange { case keep, set(Data), remove }

    let state: HomeState
    let existing: WishItem?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var link: String
    @State private var price: String
    @State private var note: String
    @State private var mostWanted: Bool
    @State private var occasion: WishOccasion?
    @State private var image: UIImage?
    @State private var picture = PictureChange.keep
    @State private var loadingPreview = false

    init(state: HomeState, existing: WishItem?) {
        self.state = state
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _link = State(initialValue: existing?.link ?? "")
        _price = State(initialValue: existing?.price ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _mostWanted = State(initialValue: existing?.mostWanted ?? false)
        _occasion = State(initialValue: existing?.occasion)
        _image = State(initialValue: existing.flatMap { WishImage.load($0.id) })
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var url: URL? {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    var body: some View {
        BilletSheet(existing == nil ? "New wish" : "Edit wish", onConfirm: { save() }, canConfirm: !trimmedTitle.isEmpty) {
                VStack(alignment: .leading, spacing: Space.l) {
                    SheetSubtitle(text: "Paste a link and we'll fill in the rest")
                    linkRow
                    if image != nil || loadingPreview { preview }
                    UsField(placeholder: String(localized: "What would you love?"), text: $title)
                    UsField(placeholder: String(localized: "Price (optional)"), text: $price)
                    UsField(placeholder: String(localized: "Colour, size, details (optional)"), text: $note)
                    mostWantedToggle
                    occasionPicker
                    if let existing { existingActions(existing) }
                }
        }
        .task(id: link) { await fetchPreview() }
    }

    private var linkRow: some View {
        HStack(spacing: Space.m) {
            UsField(placeholder: String(localized: "Link (optional)"), text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            PasteButton(payloadType: URL.self) { urls in
                guard let pasted = urls.first else { return }
                Task { @MainActor in link = pasted.absoluteString }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .tint(.honey)
        }
    }

    private var preview: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Ink.surfaceRaised
                ProgressView()
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if image != nil {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        image = nil
                        picture = .remove
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.ourioMicro)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.45), in: .circle)
                }
                .buttonStyle(PressScaleStyle())
                .padding(Space.s)
                .accessibilityLabel("Remove picture")
            }
        }
    }

    private var mostWantedToggle: some View {
        Toggle(isOn: $mostWanted.animation(.snappy(duration: 0.2))) {
            Label {
                Text("Most wanted")
                    .font(.ourioCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            } icon: {
                Image(systemName: mostWanted ? "star.fill" : "star")
                    .foregroundStyle(mostWanted ? Color.blushPink : Ink.textTertiary)
            }
        }
        .tint(.blushPink)
        .fieldSurface()
    }

    /// The calendar's coming days that gifts are for: the couple's own events and their anniversaries.
    private var occasions: [WishOccasion] {
        state.us.upcoming(togetherSince: state.togetherSince, limit: 60)
            .filter { row in
                switch row.source {
                case .event: true
                case .milestone: row.id.hasPrefix("year-")
                case .date: false
                }
            }
            .prefix(8)
            .map { WishOccasion(title: $0.title, date: $0.date) }
    }

    private var occasionPicker: some View {
        Menu {
            Button(String(localized: "No occasion")) { occasion = nil }
            ForEach(occasions, id: \.self) { choice in
                Button("\(choice.title) · \(choice.date.formatted(.dateTime.day().month()))") { occasion = choice }
            }
        } label: {
            HStack {
                Label {
                    Text(occasion.map { String(localized: "For \($0.title)") } ?? String(localized: "For an occasion"))
                        .font(.ourioCallout.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(occasion == nil ? Ink.textTertiary : Ink.accentText)
                }
                Spacer(minLength: 8)
                Text(occasion?.date.formatted(.dateTime.day().month()) ?? String(localized: "None"))
                    .font(.ourioCallout)
                    .foregroundStyle(Ink.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.textTertiary)
            }
            .fieldSurface()
        }
        .buttonStyle(PressScaleStyle())
        .disabled(occasions.isEmpty && occasion == nil)
    }

    private func existingActions(_ wish: WishItem) -> some View {
        HStack {
            Button {
                withAnimation(.snappy(duration: 0.25)) { state.us.markReceived(wish.id, by: state.viewer) }
                dismiss()
            } label: {
                Label("Got it ♥", systemImage: "heart.fill")
            }
            .foregroundStyle(Ink.accentText)
            Spacer()
            Button(role: .destructive) {
                WishImage.remove(wish.id)
                withAnimation(.snappy(duration: 0.25)) { state.us.deleteWish(wish.id) }
                dismiss()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .foregroundStyle(Ink.destructive)
        }
        .font(.ourioCallout.weight(.semibold))
        .buttonStyle(PressScaleStyle())
        .padding(.horizontal, Space.xs)
        .padding(.top, Space.s)
    }

    /// Waits for typing to settle, then asks the page for its title and picture. Only fills what is still empty.
    private func fetchPreview() async {
        guard let url, url.absoluteString != existing?.link else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        loadingPreview = image == nil
        defer { loadingPreview = false }
        guard let preview = await LinkPreview.fetch(url), !Task.isCancelled else { return }
        withAnimation(.snappy(duration: 0.25)) {
            if trimmedTitle.isEmpty, let fetched = preview.title { title = fetched }
            if image == nil, let data = preview.image, let fetched = UIImage(data: data) {
                image = fetched
                picture = .set(data)
            }
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        var wish = existing ?? WishItem(owner: state.viewer, title: trimmedTitle)
        wish.title = trimmedTitle
        wish.link = link.trimmingCharacters(in: .whitespacesAndNewlines)
        wish.price = price.trimmingCharacters(in: .whitespacesAndNewlines)
        wish.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        wish.mostWanted = mostWanted
        wish.occasion = occasion
        switch picture {
        case .keep: break
        case .set(let data): WishImage.save(data, for: wish.id)
        case .remove: WishImage.remove(wish.id)
        }
        withAnimation(.snappy(duration: 0.25)) { state.us.upsertWish(wish) }
        dismiss()
    }
}
