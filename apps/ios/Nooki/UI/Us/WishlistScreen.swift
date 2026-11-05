import SwiftUI

struct WishlistScreen: View {
    let state: HomeState

    @State private var tab = 0
    @State private var adding = false
    @State private var editing: WishItem?
    @State private var loves = Loves()
    @State private var lovesOwner = ""
    @FocusState private var lovesFocus: LovesField?

    private enum LovesField: Hashable {
        case sizes, flowers, coffee, sweets, allergies
    }

    private var us: UsStore { state.us }
    private var viewer: String { state.viewer }
    private var other: String { state.otherPartner }
    private var owner: String { tab == 0 ? viewer : other }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(title: "Wishlists", subtitle: "Little hints for each other") {
                if tab == 0 {
                    UsAddButton { adding = true }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    chips
                    if tab == 0 { mineTab } else { partnerTab }
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
        .sheet(isPresented: $adding) {
            WishEditor(state: state, existing: nil)
        }
        .sheet(item: $editing) { wish in
            WishEditor(state: state, existing: wish)
        }
        .onAppear(perform: loadLoves)
        .onChange(of: state.viewer) { _, _ in loadLoves() }
        .onChange(of: lovesFocus) { _, focused in
            if focused == nil { saveLoves() }
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            UsChip(title: "Mine", selected: tab == 0) {
                withAnimation(.snappy(duration: 0.25)) { tab = 0 }
            }
            UsChip(title: "\(other)'s", selected: tab == 1) {
                saveLoves()
                withAnimation(.snappy(duration: 0.25)) { tab = 1 }
            }
        }
    }

    private var mineTab: some View {
        let wishes = us.wishes(of: viewer)
        return VStack(alignment: .leading, spacing: 12) {
            if wishes.isEmpty {
                UsEmpty(
                    icon: .init(symbol: "heart.fill", tint: .blush),
                    title: "What would make you smile?",
                    text: "Add things you'd love. \(other) can secretly pick one to gift you."
                )
            } else {
                ForEach(wishes) { wish in
                    mineCard(wish)
                }
            }
        }
    }

    private var partnerTab: some View {
        let wishes = us.wishes(of: other)
        return VStack(alignment: .leading, spacing: 12) {
            if wishes.isEmpty {
                UsEmpty(
                    icon: .init(symbol: "gift.fill", tint: .coral),
                    title: "No hints yet",
                    text: "When \(other) adds wishes, you'll see them here."
                )
            } else {
                ForEach(wishes) { wish in
                    partnerCard(wish)
                }
            }
        }
    }

    private func mineCard(_ wish: WishItem) -> some View {
        cardBody(wish, showReserved: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onTapGesture { editing = wish }
            .contextMenu {
                if wish.reservedBy != nil {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { us.markReceived(wish.id) }
                    } label: {
                        Label("Got it! ♥", systemImage: "heart.fill")
                    }
                }
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.25)) { us.deleteWish(wish.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .accessibilityAddTraits(.isButton)
    }

    private func partnerCard(_ wish: WishItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cardBody(wish, showReserved: false)
            if wish.reservedBy == viewer {
                HStack(spacing: 10) {
                    Text("You're gifting this ✓")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.accentText)
                    Spacer(minLength: 0)
                    Button("Release") {
                        withAnimation(.snappy(duration: 0.25)) { us.toggleReserve(wish.id, by: viewer) }
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.textSecondary)
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { us.toggleReserve(wish.id, by: viewer) }
                } label: {
                    Text("I'll gift this")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Ink.heroInk)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(.honeyGradient))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
    }

    private func cardBody(_ wish: WishItem, showReserved: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wish.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.text)
                Spacer(minLength: 0)
                Text(String(repeating: "♥", count: max(0, wish.want)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.blushPink)
            }
            if !wish.price.isEmpty {
                Text(wish.price)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.blushPink)
            }
            if let url = URL(string: wish.link), let host = url.host() {
                Link(host, destination: url)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Ink.accentText)
            }
            if showReserved && wish.reservedBy != nil {
                Label("Someone is planning something", systemImage: "gift.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Ink.surfaceRaised, in: .capsule)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var giftedSection: some View {
        let items = us.gifted(to: owner)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Gifted")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Ink.text)
                ForEach(items) { wish in
                    HStack(spacing: 10) {
                        UsIcon(glyph: .init(symbol: "gift.fill", tint: .coral), size: 24)
                        Text(wish.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Ink.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if let date = wish.gifted {
                            Text(date, format: .dateTime.day().month())
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Ink.textSecondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Ink.surface, in: .rect(cornerRadius: Radius.control, style: .continuous))
                }
            }
        }
    }

    private var lovesSection: some View {
        let editable = owner == viewer
        return VStack(alignment: .leading, spacing: 10) {
            Text(owner == viewer ? "What I love" : "What \(other) loves")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Ink.text)
            VStack(spacing: 0) {
                lovesRow(.init(symbol: "tshirt.fill", tint: .sky), "Sizes", .sizes, \.sizes, editable: editable)
                lovesDivider
                lovesRow(.init(symbol: "camera.macro", tint: .blush), "Flowers", .flowers, \.flowers, editable: editable)
                lovesDivider
                lovesRow(.init(symbol: "cup.and.saucer.fill", tint: .honey), "Coffee order", .coffee, \.coffee, editable: editable)
                lovesDivider
                lovesRow(.init(symbol: "birthday.cake.fill", tint: .coral), "Sweets", .sweets, \.sweets, editable: editable)
                lovesDivider
                lovesRow(.init(symbol: "exclamationmark.triangle.fill", tint: .sun), "Allergies", .allergies, \.allergies, editable: editable)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Ink.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private var lovesDivider: some View {
        Rectangle()
            .fill(Ink.separator)
            .frame(height: 1)
    }

    private func lovesRow(
        _ icon: UsGlyph,
        _ label: String,
        _ field: LovesField,
        _ keyPath: WritableKeyPath<Loves, String>,
        editable: Bool
    ) -> some View {
        HStack(spacing: 10) {
            UsIcon(glyph: icon, size: 26)
            Text(label)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.textSecondary)
                .frame(width: 100, alignment: .leading)
            if editable {
                TextField(
                    "",
                    text: Binding(
                        get: { loves[keyPath: keyPath] },
                        set: { loves[keyPath: keyPath] = $0 }
                    ),
                    prompt: Text("—").foregroundStyle(Ink.textTertiary)
                )
                .focused($lovesFocus, equals: field)
                .onSubmit { saveLoves() }
                .multilineTextAlignment(.trailing)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.text)
            } else {
                Text(us.loves(of: owner)[keyPath: keyPath].isEmpty ? "—" : us.loves(of: owner)[keyPath: keyPath])
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Ink.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 42)
    }

    private func loadLoves() {
        guard lovesOwner != viewer else { return }
        loves = us.loves(of: viewer)
        lovesOwner = viewer
    }

    private func saveLoves() {
        guard lovesOwner == viewer else { return }
        withAnimation(.snappy(duration: 0.25)) { us.setLoves(loves, for: viewer) }
    }
}

struct WishEditor: View {
    let state: HomeState
    let existing: WishItem?

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var link: String
    @State private var price: String
    @State private var want: Int

    init(state: HomeState, existing: WishItem?) {
        self.state = state
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _link = State(initialValue: existing?.link ?? "")
        _price = State(initialValue: existing?.price ?? "")
        _want = State(initialValue: existing?.want ?? 2)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            UsSheetHeader(
                title: existing == nil ? "New wish" : "Edit wish",
                subtitle: "Only you know what you'd love"
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    UsField(placeholder: "What would you love?", text: $title)
                    UsField(placeholder: "Link (optional)", text: $link)
                    UsField(placeholder: "Price (optional)", text: $price)
                    heartsPicker
                    UsPrimaryButton(title: "Save") { save() }
                        .opacity(trimmedTitle.isEmpty ? 0.45 : 1)
                        .disabled(trimmedTitle.isEmpty)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .usSheet(detents: [.medium, .large])
    }

    private var heartsPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How much do you want it?")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.textSecondary)
            HStack(spacing: 12) {
                ForEach(1...3, id: \.self) { value in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { want = value }
                    } label: {
                        Image(systemName: value <= want ? "heart.fill" : "heart")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(value <= want ? Color.blushPink : Ink.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) hearts")
                }
            }
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        withAnimation(.snappy(duration: 0.25)) {
            state.us.upsertWish(WishItem(
                id: existing?.id ?? UUID(),
                owner: state.viewer,
                title: trimmedTitle,
                link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                price: price.trimmingCharacters(in: .whitespacesAndNewlines),
                want: want,
                reservedBy: existing?.reservedBy
            ))
        }
        dismiss()
    }
}
