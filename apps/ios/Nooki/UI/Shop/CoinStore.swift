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

/// The store's top card: Mochi in a crown on honey, with a slow shine across it.
struct PlusHero: View {
    let mockStore: Bool
    @AppStorage(PlusPass.key) private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shine = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.l) {
                mochi
                VStack(alignment: .leading, spacing: 2) {
                    Text("Billet Plus")
                        .font(.nookiLargeTitle)
                    Text(on ? "On for the two of you (test)" : "For the two of you, every month")
                        .font(.nookiCallout)
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(PlusPass.perks, id: \.text) { perk in
                    Label(perk.text, systemImage: perk.symbol)
                        .font(.nookiCallout.weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                }
            }

            action
        }
        .foregroundStyle(Ink.heroInk)
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.honeyGradient, in: .rect(cornerRadius: Radius.hero, style: .continuous))
        .overlay { shineBand.clipShape(.rect(cornerRadius: Radius.hero, style: .continuous)).allowsHitTesting(false) }
        .shadow(color: Color.honeyDeep.opacity(0.35), radius: 14, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plusHero")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: false).delay(0.6)) { shine = true }
        }
    }

    private var mochi: some View {
        Group {
            if let image = UIImage(named: CatCoat.current().avatar) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "cat.fill").font(.system(size: 34)).foregroundStyle(Ink.heroInk)
            }
        }
        .frame(width: 72, height: 72)
        .background(.white.opacity(0.55), in: .circle)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
        .overlay(alignment: .top) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28))
                .foregroundStyle(Color(hex: 0xFFE07A))
                .shadow(color: Color.honeyDeep, radius: 0, x: 0, y: 1.5)
                .rotationEffect(.degrees(-10))
                .offset(y: -20)
        }
        .padding(.top, 14)
        .accessibilityHidden(true)
    }

    private var shineBand: some View {
        GeometryReader { geometry in
            LinearGradient(colors: [.clear, .white.opacity(0.42), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geometry.size.width * 0.35)
                .rotationEffect(.degrees(18))
                .offset(x: shine ? geometry.size.width * 1.2 : -geometry.size.width * 0.5)
                .opacity(reduceMotion ? 0 : 1)
        }
    }

    @ViewBuilder private var action: some View {
        if mockStore {
            Button {
                on.toggle()
            } label: {
                Text(on ? "Turn off (test)" : "Try Billet Plus · \(PlusPass.price) / month")
                    .font(.nookiHeadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(on ? .white.opacity(0.6) : .white)
            .foregroundStyle(Ink.heroInk)
            .accessibilityIdentifier("plusMock")
        } else {
            Text("\(PlusPass.price) / month · coming soon")
                .font(.nookiHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.m)
                .background(.white.opacity(0.5), in: .capsule)
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
                    buying: model.status == .buying(pack.id), isFit: pack.id == fit?.id
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
    let isFit: Bool
    let buy: () -> Void

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
            Button(action: buy) {
                Group {
                    if buying {
                        ProgressView()
                    } else {
                        Text(pack.displayPrice).font(.nookiHeadline.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .shopButton(prominent: badge != nil || isFit)
            .controlSize(.large)
            .disabled(buying)
            .accessibilityLabel("Buy \(pack.stamps) coins for \(pack.displayPrice)")
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: Radius.hero, warm: true)
        .overlay {
            if isFit {
                RoundedRectangle(cornerRadius: Radius.hero, style: .continuous).strokeBorder(Color.honey, lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge {
                Text(badge)
                    .font(.nookiCaption.weight(.bold))
                    .foregroundStyle(Ink.heroInk)
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, 5)
                    .background(.honeyGradient, in: .capsule)
                    .padding(Space.m)
            }
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
                            .shadow(color: Color.honeyDeep.opacity(0.35), radius: 2, y: 2)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
