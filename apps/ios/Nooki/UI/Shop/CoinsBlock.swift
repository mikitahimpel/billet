import SwiftUI
import WidgetBridge
import Wire

/// The Coins block in the Shop's Today, where the header's coins lead. While the server sells no coins (the
/// `payments` flag, docs/payments.md) it says how the couple earns them and where the latest went; once it does, it
/// shows the coin packs.
struct CoinsBlock: View {
    let state: HomeState

    enum Mode: Hashable {
        case packs
        case earn

        /// Packs only when the server turned payments on for this pair.
        static func of(_ flags: RemoteFlags) -> Mode {
            flags.variant(of: CoinsBlock.payments) == "on" ? .packs : .earn
        }
    }

    /// The server's switch for selling coins; `off` until purchases exist.
    nonisolated static let payments = Experiment(key: "payments", variants: ["off", "on"])

    private var mode: Mode { .of(state.rooms.remote) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ShopSectionHeader(title: "Coins", symbol: "circle.hexagongrid.fill", tint: ShopInk.gold) {
                Text("\(state.shop.coins) now")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            switch mode {
            case .packs: packs
            case .earn:
                waysCard
                recent
            }
        }
        .padding(.horizontal, Space.l)
        .task { await state.shop.loadHistory() }
    }

    // MARK: Packs

    private var packs: some View {
        VStack(spacing: Space.s) {
            ForEach(CoinPackOffer.bundled) { pack in
                HStack(spacing: Space.m) {
                    CoinIcon(size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.displayName)
                            .font(.nookiHeadline)
                            .foregroundStyle(Ink.text)
                        Text(pack.description)
                            .font(.nookiCaption)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("$\(pack.price)")
                        .font(.nookiHeadline.monospacedDigit())
                        .foregroundStyle(Ink.accentText)
                }
                .padding(Space.m)
                .shopCard()
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Earning

    private var waysCard: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(ways, id: \.text) { way in
                Label {
                    Text(way.text)
                        .font(.nookiCallout)
                        .foregroundStyle(Ink.text)
                } icon: {
                    Image(systemName: way.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.honey)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shopCard()
    }

    private var ways: [(symbol: String, text: String)] { [
        ("note.text", "Send each other notes and photos"),
        ("heart.fill", "Look after \(state.petName) and play together"),
        ("gift.fill", "Open the daily gift"),
        ("checklist", "Tick off things you want to do"),
        ("sparkles", "Match on a date idea, then rate the date"),
        ("shippingbox.fill", "Mark a wished-for gift as received"),
        ("square.grid.2x2.fill", "Complete a collection"),
    ] }

    @ViewBuilder private var recent: some View {
        if !state.shop.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Recently")
                    .font(.nookiHeadline)
                    .foregroundStyle(Ink.text)
                    .padding(.bottom, Space.s)
                ForEach(state.shop.history, id: \.id) { entry in
                    HistoryRow(line: CoinLine(entry))
                    if entry.id != state.shop.history.last?.id { Divider().overlay(Ink.separator) }
                }
            }
            .padding(Space.m)
            .shopCard()
            .accessibilityIdentifier("coinHistory")
        }
    }
}

private struct HistoryRow: View {
    let line: CoinLine

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: line.symbol)
                .font(.nookiCallout.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.honey)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.text)
                Text(line.date, format: .relative(presentation: .named))
                    .font(.nookiCaption)
                    .foregroundStyle(Ink.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(line.amount)
                .font(.nookiHeadline.monospacedDigit())
                .foregroundStyle(line.isGain ? Ink.accentText : Ink.textSecondary)
        }
        .padding(.vertical, Space.s)
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

/// A coin pack as `coin-packs.json` lists it, the one list the server and the store share (docs/payments.md).
nonisolated struct CoinPackOffer: Codable, Hashable, Identifiable {
    let id: String
    let coins: Int
    /// The reference price in US dollars, such as `"0.99"`.
    let price: String
    let displayName: String
    let description: String

    private struct File: Codable {
        let packs: [CoinPackOffer]
    }

    static func decode(_ data: Data) throws -> [CoinPackOffer] {
        try JSONDecoder().decode(File.self, from: data).packs
    }

    /// The packs bundled with the app; none if the file is missing.
    static let bundled: [CoinPackOffer] = {
        guard let url = Bundle.main.url(forResource: "coin-packs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? decode(data)) ?? []
    }()
}
