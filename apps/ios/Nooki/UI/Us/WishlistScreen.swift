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
        BilletSheet("Wishlists", scrolls: false) {
        VStack(spacing: 0) {
            SheetSubtitle(text: "Little hints for each other")
                .padding(.horizontal, Space.gutter)
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
        .toolbar {
            if mine {
                ToolbarItem(placement: .topBarLeading) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add")
                }
            }
        }
        }
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
            FilterChip(String(localized: "Mine"), isSelected: mine) {
                withAnimation(.snappy(duration: 0.25)) { mine = true }
            }
            FilterChip(String(localized: "\(otherName)'s"), isSelected: !mine) {
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
                EmptyState(
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
                EmptyState(
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
        .padding(.horizontal, CardMetrics.padding)
        .padding(.vertical, Space.m)
        .cardSurface()
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
                        .clipShape(.rect(cornerRadius: Radius.inner, style: .continuous))
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
        BilletSheet("What I love", onConfirm: save) {
                VStack(alignment: .leading, spacing: 14) {
                    SheetSubtitle(text: "So \(state.profile.name(of: state.otherPartner)) always gets it right")
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
                }
        }
        .onAppear { loves = state.us.loves(of: state.viewer) }
    }

    private func save() {
        state.us.setLoves(loves, for: state.viewer)
        dismiss()
    }
}
