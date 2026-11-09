import Payments
import SwiftUI
import Design

/// Billet Plus, the pair's monthly subscription. What it gives isn't built yet, so a mock build turns it on for this
/// phone only and a StoreKit build says it is coming.
enum PlusPass {
    static let key = "plus.mockOn"
    static let price = "$4.99"

    static let perks: [(symbol: String, text: String)] = [
        ("calendar.badge.plus", "Coins every day"),
        ("multiply.circle.fill", "Double coins from games and care"),
        ("paintpalette.fill", "Every ink"),
        ("tshirt.fill", "A new coat or accessory every month"),
        ("star.circle.fill", "A Plus badge on your avatars"),
    ]
}

/// The store's top card: Mochi in a crown on a warm card.
struct PlusHero: View {
    let mockStore: Bool
    @AppStorage(PlusPass.key) private var on = false

    var body: some View {
        Card(warm: true) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.l) {
                    mochi
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Billet Plus")
                            .font(.nookiLargeTitle)
                            .foregroundStyle(Ink.text)
                        Text(on ? "On for the two of you (test)" : "For the two of you, every month")
                            .font(.nookiCallout)
                            .foregroundStyle(Ink.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(PlusPass.perks, id: \.text) { perk in
                        Label(perk.text, systemImage: perk.symbol)
                            .font(.nookiCallout)
                            .foregroundStyle(Ink.text)
                            .symbolRenderingMode(.hierarchical)
                    }
                }

                action
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plusHero")
    }

    private var mochi: some View {
        Group {
            if let image = UIImage(named: CatCoat.current().avatar) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cat.fill").font(.largeTitle).foregroundStyle(Ink.heroInk)
            }
        }
        .frame(width: 72, height: 72)
        .background(Ink.surfaceRaised, in: .circle)
        .clipShape(.circle)
        .overlay(alignment: .top) {
            Image(systemName: "crown.fill")
                .font(.title)
                .foregroundStyle(Color.honey)
                .rotationEffect(.degrees(-10))
                .offset(y: -20)
        }
        .padding(.top, 14)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var action: some View {
        if mockStore {
            PrimaryButton(on ? "Turn off (test)" : "Try Billet Plus · \(PlusPass.price) / month") { on.toggle() }
                .accessibilityIdentifier("plusMock")
        } else {
            Text("\(PlusPass.price) / month · coming soon")
                .font(.nookiHeadline)
                .foregroundStyle(Ink.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Size.button)
                .background(Ink.surfaceRaised, in: .capsule)
        }
    }
}

/// The packs on sale as big cards, each with a pile that grows with the pack and a big price button.
struct PackStore: View {
    let model: CoinPacksModel
    /// The pack that covers a waiting buy.
    let fit: StampPack?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Coins")
                .font(.nookiTitle)
                .foregroundStyle(Ink.text)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.packs.enumerated()), id: \.element.id) { index, pack in
                PackCard(
                    pack: pack, tier: min(index, Self.piles.count - 1), badge: badge(for: index, of: model.packs),
                    buying: model.status == .buying(pack.id), locked: model.isBuying, isFit: pack.id == fit?.id
                ) {
                    Task { await model.buy(pack) }
                }
            }
            if let line = statusLine {
                Text(line)
                    .font(.nookiCallout)
                    .foregroundStyle(Ink.textSecondary)
                    .accessibilityIdentifier("packStatus")
            }
        }
        .sensoryFeedback(.success, trigger: model.status) { _, new in
            if case .bought = new { true } else { false }
        }
    }

    /// Coins per row of the pile, bottom row first.
    static let piles: [[Int]] = [[2, 1], [3, 2, 1], [4, 3, 2, 1]]

    /// The middle pack is the popular one, the biggest the best value, by what its coins cost against the smallest.
    private func badge(for index: Int, of packs: [StampPack]) -> String? {
        guard packs.count >= 3 else { return nil }
        if index == packs.count - 1, let more = Self.moreCoins(packs[index], than: packs[0]), more >= 5 {
            return "Best value +\(more)%"
        }
        return index == 1 ? "Popular" : nil
    }

    /// How many percent more coins per dollar `pack` gives than `base`, from the reference prices.
    static func moreCoins(_ pack: StampPack, than base: StampPack) -> Int? {
        let catalog = StampPackCatalog.standard
        guard let big = catalog.definition(pack.id), let small = catalog.definition(base.id),
              let bigPrice = Double(big.price), let smallPrice = Double(small.price), smallPrice > 0, bigPrice > 0
        else { return nil }
        let rate = Double(big.stamps) / bigPrice, baseRate = Double(small.stamps) / smallPrice
        return Int(((rate / baseRate - 1) * 100).rounded())
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

private struct PackCard: View {
    let pack: StampPack
    let tier: Int
    let badge: String?
    let buying: Bool
    /// Some pack is being bought, this one or another.
    let locked: Bool
    let isFit: Bool
    let buy: () -> Void

    /// Honey for the pack worth noticing, the quiet capsule for the others.
    @ViewBuilder private var priceButton: some View {
        let label = Button(action: buy) {
            if buying {
                ProgressView()
            } else {
                Text(pack.displayPrice).monospacedDigit()
            }
        }
        if badge != nil || isFit {
            label.buttonStyle(PrimaryButtonStyle())
        } else {
            label.buttonStyle(SecondaryButtonStyle())
        }
    }

    var body: some View {
        VStack(spacing: Space.l) {
            HStack(spacing: Space.l) {
                CoinPile(rows: PackStore.piles[tier])
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.stamps.formatted())
                        .font(.nookiLargeTitle.monospacedDigit())
                        .foregroundStyle(Ink.text)
                    Text("coins")
                        .font(.nookiCallout)
                        .foregroundStyle(Ink.textSecondary)
                    if isFit {
                        Text("Covers what you need")
                            .font(.nookiCaption.weight(.semibold))
                            .foregroundStyle(Ink.accentText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            priceButton
                .disabled(locked)
            .accessibilityLabel("Buy \(pack.stamps) coins for \(pack.displayPrice)")
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .cardSurface(warm: true)
        .overlay {
            if isFit {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.honey, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge { Chip(badge, style: .honey).padding(Space.m) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(isFit ? "fitPack" : pack.id)
    }
}

/// Coins heaped in a pyramid: `rows` is how many sit in each row, bottom first.
private struct CoinPile: View {
    let rows: [Int]

    var body: some View {
        VStack(spacing: -14) {
            ForEach(Array(rows.reversed().enumerated()), id: \.offset) { _, count in
                HStack(spacing: -8) {
                    ForEach(0..<count, id: \.self) { _ in
                        CoinIcon(size: 34)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
