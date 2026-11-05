import Payments
import SwiftUI
import WidgetBridge
import Wire

/// What the header's coins open, on any tab: the balance, the coin packs and Billet Plus, then how the couple earns
/// coins and where the latest went. The one place that sells coins; Home itself never does.
struct CoinsSheet: View {
    let state: HomeState
    /// Nil in a build without a server: then nothing is sold.
    let packs: CoinPacksModel?
    var ask = CoinsAsk(missing: 0, retry: nil)
    @Environment(\.dismiss) private var dismiss

    private var sellsPacks: Bool {
        packs != nil && CoinPacksModel.sells(state.rooms.remote, mockStore: AppPayments.isMock)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                SheetHeader(title: "Coins", chips: { EmptyView() }, close: { dismiss() })
                balance
                if let retry = ask.retry { ShortBanner(state: state, retry: retry) { dismiss() } }
                if let packs, sellsPacks {
                    PacksList(model: packs, fit: CoinPacksModel.fit(for: missing, in: packs.packs))
                    PlusCard(mockStore: AppPayments.isMock)
                }
                waysCard
                recent
            }
            .padding(.horizontal, Space.gutter)
            .padding(.vertical, Space.l)
        }
        .scrollIndicators(.hidden)
        .tint(.honey)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Ink.screen)
        .accessibilityIdentifier("coinsSheet")
        .task { await state.shop.loadHistory() }
        .task { if sellsPacks { await packs?.load() } }
    }

    /// What the waiting buy still needs, as the balance stands now.
    private var missing: Int { ask.retry.map { max(0, $0.cost - state.shop.coins) } ?? 0 }

    private var balance: some View {
        HStack(spacing: Space.l) {
            CoinIcon(size: 56)
                .shadow(color: Color.honeyDeep.opacity(0.45), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.shop.coins)")
                    .font(.nookiLargeTitle.monospacedDigit())
                    .foregroundStyle(Ink.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: state.shop.coins)
                Text("coins for the two of you")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.gutter)
        .nookiCard(radius: Radius.hero, warm: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coinBalance")
    }

    // MARK: Earning

    private var waysCard: some View {
        NookiSection(header: "How to earn") {
            ForEach(ways, id: \.text) { way in
                NookiRowLabel(title: way.text, symbol: way.symbol, tint: way.tint)
            }
        }
    }

    private var ways: [(symbol: String, tint: UsTint, text: String)] { [
        ("note.text", .sun, "Send each other notes and photos"),
        ("heart.fill", .blush, "Look after \(state.petName) and play together"),
        ("gift.fill", .coral, "Open the daily gift"),
        ("checklist", .sage, "Tick off things you want to do"),
        ("sparkles", .lilac, "Match on a date idea, then rate the date"),
        ("shippingbox.fill", .sky, "Mark a wished-for gift as received"),
        ("square.grid.2x2.fill", .honey, "Complete a collection"),
    ] }

    @ViewBuilder private var recent: some View {
        if !state.shop.history.isEmpty {
            NookiSection(header: "Recently") {
                ForEach(state.shop.history, id: \.id) { entry in
                    HistoryRow(line: CoinLine(entry))
                }
            }
            .accessibilityIdentifier("coinHistory")
        }
    }
}

private struct HistoryRow: View {
    let line: CoinLine

    var body: some View {
        NookiRowLabel(title: line.title, detail: line.date.formatted(.relative(presentation: .named)),
                      symbol: line.symbol, tint: line.isGain ? .honey : .sky) {
            Text(line.amount)
                .font(.nookiHeadline.monospacedDigit())
                .foregroundStyle(line.isGain ? Ink.accentText : Ink.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One wallet entry as the Coins block reads it: what it was for, from its id and ref, and the signed amount.
struct CoinLine: Hashable {
    let symbol: String
    let title: String
    let amount: String
    let isGain: Bool
    let date: Date

    init(_ entry: CoinEntry) {
        date = Date(timeIntervalSince1970: Double(entry.at) / 1000)
        isGain = entry.amount >= 0
        amount = entry.amount > 0 ? "+\(entry.amount)" : entry.amount < 0 ? "−\(-entry.amount)" : "0"
        switch entry.kind {
        case .earn:
            symbol = "sparkles"
            title = Self.earned(entry.id)
        case .buy:
            symbol = "creditcard.fill"
            title = "Coins bought"
        case .spend:
            symbol = "bag.fill"
            title = Self.name(of: entry.ref)
        case .refund:
            symbol = "arrow.uturn.backward"
            title = "Refund"
        case .gift:
            symbol = "gift.fill"
            if entry.ref == "welcome" {
                title = "Welcome coins"
            } else if entry.amount == 0 {
                title = "Daily gift: \(Self.name(of: entry.ref))"
            } else {
                title = "Daily gift"
            }
        case .bonus:
            symbol = "checkmark.seal.fill"
            title = "\(Catalog.collections.first { $0.id == entry.ref }?.name ?? "Collection") bonus"
        }
    }

    /// App earns are `earn:<what>:<ref>`; the room's own, for notes and care, are `earn:<entry>`.
    static func earned(_ id: String) -> String {
        let parts = id.split(separator: ":")
        guard parts.count >= 3 else { return "Notes and care" }
        switch parts[1] {
        case "wish": return "A wish came true"
        case "date": return "A date you both liked"
        case "plan": return "A date, rated"
        case "list": return "Ticked off a list"
        case "moment": return "A moment"
        case "note": return "A note"
        default: return "Coins earned"
        }
    }

    /// A piece, a set, an ink or the treat, by its id.
    static func name(of ref: String) -> String {
        if ref == "treat" { return "A treat" }
        if let item = Catalog.item(ref) { return item.name }
        if let bundle = ShopOffers.bundles.first(where: { $0.id == ref }) { return bundle.name }
        if let set = ShopOffers.featuredSets.first(where: { $0.id == ref }) { return set.name }
        if let ink = PaletteInk.bundled.first(where: { $0.id == ref }) { return "\(ink.name) ink" }
        return ref
    }
}

/// The buy the balance didn't cover: how many coins it still needs, and, once they're there, finishing it in one tap.
private struct ShortBanner: View {
    let state: HomeState
    let retry: CoinsAsk.Retry
    let done: () -> Void

    private var missing: Int { max(0, retry.cost - state.shop.coins) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if missing > 0 {
                Text("You need \(missing) more")
                    .font(.nookiHeadline.monospacedDigit())
                    .foregroundStyle(Ink.text)
                    .contentTransition(.numericText())
                Text("for \(retry.title), \(retry.cost) coins.")
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
            } else {
                Text("You have enough now")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                Button {
                    if state.shop.finish(retry) { done() }
                } label: {
                    HStack(spacing: Space.s) {
                        Text("Buy \(retry.title) for")
                        CoinPrice(price: retry.cost, was: nil)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .shopButton()
                .accessibilityIdentifier("finishBuy")
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shopCard()
        .animation(.snappy, value: missing)
        .accessibilityIdentifier("shortBanner")
    }
}

/// The packs on sale, each a button with the store's price.
private struct PacksList: View {
    let model: CoinPacksModel
    /// The pack that covers a waiting buy, shown first among equals.
    let fit: StampPack?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Get more coins")
                .font(.nookiCaption.weight(.semibold))
                .foregroundStyle(Ink.textSecondary)
                .padding(.horizontal, Space.l)
                .accessibilityAddTraits(.isHeader)
            ForEach(model.packs) { pack in
                PackRow(pack: pack, buying: model.status == .buying(pack.id), isFit: pack.id == fit?.id) {
                    Task { await model.buy(pack) }
                }
            }
            if let line = statusLine {
                Text(line)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
                    .accessibilityIdentifier("packStatus")
            }
        }
        .sensoryFeedback(.success, trigger: model.status) { _, new in
            if case .bought = new { true } else { false }
        }
    }

    private var statusLine: String? {
        switch model.status {
        case .idle, .buying: nil
        case .waiting: "Waiting for approval. The coins arrive once it's given."
        case .bought(let coins): "+\(coins) coins. Enjoy!"
        case .failed(let message): message
        }
    }
}

private struct PackRow: View {
    let pack: StampPack
    let buying: Bool
    let isFit: Bool
    let buy: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            CoinIcon(size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.displayName)
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                if isFit {
                    Text("Covers it")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(Ink.accentText)
                }
                Text(pack.description)
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: buy) {
                if buying {
                    ProgressView().frame(minWidth: 56)
                } else {
                    Text(pack.displayPrice).monospacedDigit().frame(minWidth: 56)
                }
            }
            .shopButton(prominent: isFit)
            .disabled(buying)
            .accessibilityLabel("Buy \(pack.stamps) coins for \(pack.displayPrice)")
        }
        .padding(Space.l)
        .shopCard()
        .overlay {
            if isFit {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.honey, lineWidth: 2)
            }
        }
        .accessibilityIdentifier(isFit ? "fitPack" : pack.id)
    }
}

/// Billet Plus, the subscription. What it costs and gives isn't settled yet, so the card is a placeholder: a mock
/// build turns it on for this phone only, and a StoreKit build says it is coming.
private struct PlusCard: View {
    let mockStore: Bool
    @AppStorage("plus.mockOn") private var mockOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                UsIcon(glyph: .init(symbol: "sparkles", tint: .lilac), size: 34)
                Text("Billet Plus")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                if mockOn {
                    Text("On (test)")
                        .font(.nookiCaption.weight(.semibold))
                        .foregroundStyle(Ink.accentText)
                }
            }
            Text("More for the two of you, every month. Details soon.")
                .font(.nookiCallout)
                .foregroundStyle(Ink.textSecondary)
            if mockStore {
                Button(mockOn ? "Turn off (test)" : "Try Billet Plus (test)") { mockOn.toggle() }
                    .shopButton(prominent: !mockOn)
                    .accessibilityIdentifier("plusMock")
            } else {
                Text("Coming soon")
                    .font(.nookiCaption.weight(.semibold))
                    .foregroundStyle(Ink.textSecondary)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shopCard()
    }
}
