import SwiftUI
import Design

struct WishlistScreen: View {
    let state: HomeState

    @State private var mine = true
    @State private var adding = false
    @State private var editing: WishItem?
    @State private var editingLoves = false

    private var us: UsStore { state.us }
    private var viewer: String { state.viewer }
    private var other: String { state.otherPartner }
    private var otherName: String { state.profile.name(of: other) }
    private var owner: String { mine ? viewer : other }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: "Wishlists", subtitle: "Little hints for each other") {
                if mine {
                    UsAddButton { adding = true }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    chips
                    if mine { mineTab } else { partnerTab }
                    giftedSection
                    lovesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .usSheet()
        .task { await state.gifts.refresh() }
        .sheet(isPresented: $adding) {
            WishEditor(state: state, existing: nil)
        }
        .sheet(item: $editing) { wish in
            WishEditor(state: state, existing: wish)
        }
        .sheet(isPresented: $editingLoves) {
            LovesEditor(state: state)
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            UsChip(title: String(localized: "Mine"), selected: mine) {
                withAnimation(.snappy(duration: 0.25)) { mine = true }
            }
            UsChip(title: String(localized: "\(otherName)'s"), selected: !mine) {
                withAnimation(.snappy(duration: 0.25)) { mine = false }
            }
        }
    }

    // MARK: Mine

    private var mineTab: some View {
        let wishes = us.wishes(of: viewer)
        return VStack(alignment: .leading, spacing: 12) {
            if us.surpriseComing(for: viewer) {
                Label("\(otherName) is planning a surprise 🤫", systemImage: "gift.fill")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Ink.surfaceRaised, in: .capsule)
            }
            if wishes.isEmpty {
                UsEmpty(
                    icon: .init(symbol: "heart.fill", tint: .blush),
                    title: String(localized: "What would make you smile?"),
                    text: String(
                        localized: "Paste a link or type a wish. \(otherName) can secretly pick one to gift you.")
                )
            } else {
                ForEach(wishes) { wish in
                    Button { editing = wish } label: {
                        WishCard(wish: wish)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            withAnimation(.snappy(duration: 0.25)) { us.markReceived(wish.id, by: viewer) }
                        } label: {
                            Label("Got it ♥", systemImage: "heart.fill")
                        }
                        Button(role: .destructive) {
                            WishImage.remove(wish.id)
                            withAnimation(.snappy(duration: 0.25)) { us.deleteWish(wish.id) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Partner

    private var partnerTab: some View {
        let wishes = us.wishes(of: other)
        return VStack(alignment: .leading, spacing: 12) {
            if wishes.isEmpty {
                UsEmpty(
                    icon: .init(symbol: "gift.fill", tint: .coral),
                    title: String(localized: "No hints yet"),
                    text: String(localized: "When \(otherName) adds wishes, you'll see them here.")
                )
            } else {
                ForEach(wishes) { wish in
                    WishCard(wish: wish, linked: true) { giverRow(wish) }
                }
                Text("Your picks stay secret. \(otherName) only sees that a surprise is coming.")
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func animate(_ change: () -> Void) {
        withAnimation(.snappy(duration: 0.25), change)
    }

    @ViewBuilder
    private func giverRow(_ wish: WishItem) -> some View {
        switch us.plan(for: wish.id, viewer: viewer)?.stage {
        case nil:
            Button { animate { us.pick(wish.id, by: viewer) } } label: {
                Label("I'll get this", systemImage: "gift.fill")
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.heroInk)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(.honeyGradient))
            }
            .buttonStyle(.plain)
        case .planning?:
            HStack(spacing: 10) {
                Text("You're getting this 🤫")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
                Spacer(minLength: 0)
                Button("Release") { animate { us.release(wish.id, by: viewer) } }
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
                    .buttonStyle(.plain)
                Button { animate { us.setStage(.bought, of: wish.id, by: viewer) } } label: {
                    Text("Bought it")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(.honeyGradient))
                }
                .buttonStyle(.plain)
            }
        case .bought?:
            HStack(spacing: 10) {
                Label("Bought. Hide it well!", systemImage: "checkmark.circle.fill")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.accentText)
                Spacer(minLength: 0)
                Button("Not yet") { animate { us.setStage(.planning, of: wish.id, by: viewer) } }
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Gifted

    @ViewBuilder
    private var giftedSection: some View {
        let items = us.gifted(to: owner)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(mine ? "Got it ♥" : "Gifted to \(otherName)")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                ForEach(items) { wish in
                    giftedRow(wish)
                }
            }
        }
    }

    private func giftedRow(_ wish: WishItem) -> some View {
        HStack(spacing: 10) {
            UsIcon(glyph: .init(symbol: "gift.fill", tint: .coral), size: 24)
            Text(wish.title)
                .font(.nookiCallout.weight(.semibold))
                .foregroundStyle(Ink.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if let giver = wish.giftedBy {
                    Text(giver == viewer ? "from you" : "from \(state.profile.name(of: giver))")
                        .font(.nookiMicro.weight(.semibold))
                        .foregroundStyle(Ink.accentText)
                }
                if let date = wish.gifted {
                    Text(date, format: .dateTime.day().month())
                        .font(.nookiMicro)
                        .foregroundStyle(Ink.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Ink.surface, in: .rect(cornerRadius: Radius.control, style: .continuous))
        .contextMenu {
            if mine {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { us.unmarkReceived(wish.id, by: viewer) }
                } label: {
                    Label("Not received yet", systemImage: "arrow.uturn.backward")
                }
            }
        }
    }

    // MARK: Loves

    private var lovesSection: some View {
        let loves = us.loves(of: owner)
        let rows = LovesRow.all.filter { mine || !loves[keyPath: $0.keyPath].isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(mine ? "What I love" : "\(otherName)'s cheat sheet")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                if mine {
                    Button("Edit") { editingLoves = true }
                        .font(.nookiCallout.weight(.semibold))
                        .foregroundStyle(Ink.accentText)
                        .buttonStyle(.plain)
                }
            }
            if rows.isEmpty {
                Text("\(otherName) hasn't filled this in yet.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.label) { index, row in
                        if index > 0 {
                            Rectangle().fill(Ink.separator).frame(height: 1)
                        }
                        let value = loves[keyPath: row.keyPath]
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            UsIcon(glyph: row.icon, size: 26)
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                            Text(row.label)
                                .font(.nookiCallout.weight(.semibold))
                                .foregroundStyle(Ink.textSecondary)
                            Spacer(minLength: 12)
                            Text(value.isEmpty ? "—" : value)
                                .font(.nookiCallout.weight(.semibold))
                                .foregroundStyle(value.isEmpty ? Ink.textTertiary : Ink.text)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
                .contentShape(.rect)
                .onTapGesture { if mine { editingLoves = true } }
            }
        }
    }
}

// MARK: - Card

private struct WishCard<Actions: View>: View {
    let wish: WishItem
    var linked = false
    @ViewBuilder var actions: Actions

    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: Radius.control, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if wish.mostWanted {
                        Label("Most wanted", systemImage: "star.fill")
                            .font(.nookiMicro.weight(.semibold))
                            .foregroundStyle(Color.blushPink)
                    }
                    Text(wish.title)
                        .font(.nookiHeadline)
                        .foregroundStyle(Ink.text)
                        .multilineTextAlignment(.leading)
                    meta
                    if let occasion = wish.occasion, occasion.daysLeft() >= 0 {
                        OccasionLine(occasion: occasion)
                    }
                    if !wish.note.isEmpty {
                        Text(wish.note)
                            .font(.nookiCaption)
                            .foregroundStyle(Ink.textSecondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .task(id: wish) { await loadImage() }
    }

    /// The phone's own picture, or, for a wish made on the partner's phone, the one its link shows, kept once fetched.
    private func loadImage() async {
        image = WishImage.load(wish.id)
        guard image == nil, let url = URL(string: wish.link), url.scheme?.hasPrefix("http") == true,
              let data = await LinkPreview.fetch(url)?.image, !Task.isCancelled else { return }
        WishImage.save(data, for: wish.id)
        image = UIImage(data: data)
    }

    @ViewBuilder
    private var meta: some View {
        let url = URL(string: wish.link)
        let host = url?.host()?.replacing(/^www\./, with: "")
        if !wish.price.isEmpty || host != nil {
            HStack(spacing: 6) {
                if !wish.price.isEmpty {
                    Text(wish.price)
                        .foregroundStyle(Color.blushPink)
                }
                if let url, let host {
                    if !wish.price.isEmpty { Text("·").foregroundStyle(Ink.textTertiary) }
                    if linked {
                        Link(destination: url) {
                            Label(host, systemImage: "arrow.up.right")
                                .labelStyle(TrailingIcon())
                        }
                        .foregroundStyle(Ink.accentText)
                    } else {
                        Text(host).foregroundStyle(Ink.textSecondary)
                    }
                }
            }
            .font(.nookiCaption.weight(.semibold))
            .lineLimit(1)
        }
    }
}

/// "For Lena's birthday · in 12 days", so the giver knows when it's needed.
private struct OccasionLine: View {
    let occasion: WishOccasion

    var body: some View {
        Label {
            Text("For \(occasion.title) · \(Self.when(occasion.daysLeft()))")
        } icon: {
            Image(systemName: "calendar")
        }
        .font(.nookiCaption.weight(.semibold))
        .foregroundStyle(Ink.accentText)
        .lineLimit(1)
    }

    static func when(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "today")
        case 1: String(localized: "tomorrow")
        default: String(localized: "in \(days) days")
        }
    }
}

extension WishCard where Actions == EmptyView {
    init(wish: WishItem) {
        self.init(wish: wish) { EmptyView() }
    }
}

private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

// MARK: - Loves

private struct LovesRow {
    let icon: UsGlyph
    let label: String
    let keyPath: WritableKeyPath<Loves, String>
    let example: String

    static let all: [LovesRow] = [
        .init(icon: .init(symbol: "tshirt.fill", tint: .sky), label: String(localized: "Sizes"), keyPath: \.sizes,
              example: String(localized: "S, jeans 26, shoes 38")),
        .init(icon: .init(symbol: "camera.macro", tint: .blush), label: String(localized: "Flowers"),
              keyPath: \.flowers,
              example: String(localized: "Peonies, no lilies")),
        .init(icon: .init(symbol: "cup.and.saucer.fill", tint: .honey), label: String(localized: "Coffee order"),
              keyPath: \.coffee, example: String(localized: "Iced oat latte")),
        .init(icon: .init(symbol: "birthday.cake.fill", tint: .coral), label: String(localized: "Sweets"),
              keyPath: \.sweets,
              example: String(localized: "Macarons, sour gummies")),
        .init(icon: .init(symbol: "exclamationmark.triangle.fill", tint: .sun), label: String(localized: "Allergies"),
              keyPath: \.allergies, example: String(localized: "Nuts, pollen")),
        .init(icon: .init(symbol: "hand.raised.fill", tint: .lilac), label: String(localized: "Please don't"),
              keyPath: \.avoid, example: String(localized: "Soft toys, anything yellow")),
    ]
}

private struct LovesEditor: View {
    let state: HomeState

    @Environment(\.dismiss) private var dismiss
    @State private var loves = Loves()

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: "What I love",
                          subtitle: "So \(state.profile.name(of: state.otherPartner)) always gets it right")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(LovesRow.all, id: \.label) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Label {
                                Text(row.label)
                            } icon: {
                                UsIcon(glyph: row.icon, size: 22)
                            }
                            .font(.nookiCaption.weight(.semibold))
                            .foregroundStyle(Ink.textSecondary)
                            UsField(placeholder: row.example, text: $loves[dynamicMember: row.keyPath])
                        }
                    }
                    PrimaryButton(String(localized: "Save")) {
                        state.us.setLoves(loves, for: state.viewer)
                        dismiss()
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .usSheet()
        .onAppear { loves = state.us.loves(of: state.viewer) }
    }
}

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
        VStack(spacing: 0) {
            UsSheetHeader(
                title: existing == nil ? "New wish" : "Edit wish",
                subtitle: "Paste a link and we'll fill in the rest"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    linkRow
                    if image != nil || loadingPreview { preview }
                    UsField(placeholder: String(localized: "What would you love?"), text: $title)
                    UsField(placeholder: String(localized: "Price (optional)"), text: $price)
                    UsField(placeholder: String(localized: "Colour, size, details (optional)"), text: $note)
                    mostWantedToggle
                    occasionPicker
                    PrimaryButton(String(localized: "Save")) { save() }
                        .opacity(trimmedTitle.isEmpty ? 0.45 : 1)
                        .disabled(trimmedTitle.isEmpty)
                        .padding(.top, 4)
                    if let existing { existingActions(existing) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .usSheet(detents: [.large])
        .task(id: link) { await fetchPreview() }
    }

    private var linkRow: some View {
        HStack(spacing: 10) {
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
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.black.opacity(0.45), in: .circle)
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("Remove picture")
            }
        }
    }

    private var mostWantedToggle: some View {
        Toggle(isOn: $mostWanted.animation(.snappy(duration: 0.2))) {
            Label {
                Text("Most wanted")
                    .font(.nookiCallout.weight(.semibold))
                    .foregroundStyle(Ink.text)
            } icon: {
                Image(systemName: mostWanted ? "star.fill" : "star")
                    .foregroundStyle(mostWanted ? Color.blushPink : Ink.textTertiary)
            }
        }
        .tint(.blushPink)
        .padding(.horizontal, Space.l)
        .frame(minHeight: 50)
        .cardSurface(radius: Radius.control)
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
                        .font(.nookiCallout.weight(.semibold))
                        .foregroundStyle(Ink.text)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(occasion == nil ? Ink.textTertiary : Ink.accentText)
                }
                Spacer(minLength: 8)
                Text(occasion?.date.formatted(.dateTime.day().month()) ?? String(localized: "None"))
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.textTertiary)
            }
            .padding(.horizontal, Space.l)
            .frame(minHeight: 50)
            .cardSurface(radius: Radius.control)
        }
        .buttonStyle(.plain)
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
            .foregroundStyle(Color.red.opacity(0.85))
        }
        .font(.nookiCallout.weight(.semibold))
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.top, 6)
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
