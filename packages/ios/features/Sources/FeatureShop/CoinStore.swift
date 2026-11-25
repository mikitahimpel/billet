#if canImport(UIKit)
  import Design
  import Payments
  import SwiftUI

  struct PackStore: View {
    let model: CoinPacksModel
    let fit: StampPack?

    var body: some View {
      VStack(alignment: .leading, spacing: Space.m) {
        SectionHeader("Coin packs")
        shelf
        if let line = statusLine {
          Text(line)
            .font(.ourioCallout)
            .foregroundStyle(Ink.textSecondary)
            .accessibilityIdentifier("packStatus")
        }
      }
      .sensoryFeedback(.success, trigger: model.status) { _, new in
        if case .bought = new { true } else { false }
      }
    }

    @ViewBuilder private var shelf: some View {
      switch model.shelf {
      case .loading:
        Card {
          HStack(spacing: Space.m) {
            ProgressView().tint(Ink.accentText)
            Text("Opening the store…")
              .font(.ourioCallout)
              .foregroundStyle(Ink.textSecondary)
          }
          .frame(maxWidth: .infinity, minHeight: Size.button)
        }
      case .ready(let packs):
        ForEach(Array(packs.enumerated()), id: \.element.id) { index, pack in
          PackCard(
            pack: pack, tier: min(index, Self.piles.count - 1), badge: badge(for: index, of: packs),
            buying: model.status == .buying(pack.id), locked: model.isBuying,
            isFit: pack.id == fit?.id
          ) {
            Task { await model.buy(pack) }
          }
        }
      case .unavailable:
        Card {
          VStack(spacing: Space.m) {
            CardHeader(
              "The store didn't open",
              detail: "Nothing was charged. You can still earn coins below.",
              symbol: "wifi.exclamationmark", tint: Ink.textSecondary, opens: false)
            RetryButton { Task { await model.load() } }
          }
        }
        .accessibilityIdentifier("storeUnavailable")
      }
    }

    /// Coins per row of the pile, bottom row first.
    static let piles: [[Int]] = [[2, 1], [3, 2, 1], [4, 3, 2, 1]]

    /// The middle pack is the popular one, the biggest the best value, by what its coins cost against the smallest.
    private func badge(for index: Int, of packs: [StampPack]) -> String? {
      guard packs.count >= 3 else { return nil }
      if index == packs.count - 1, let more = Self.moreCoins(packs[index], than: packs[0]),
        more >= 5
      {
        return "Best value +\(more)%"
      }
      return index == 1 ? "Popular" : nil
    }

    /// How many percent more coins per dollar `pack` gives than `base`, from the reference prices.
    static func moreCoins(_ pack: StampPack, than base: StampPack) -> Int? {
      let catalog = StampPackCatalog.standard
      guard let big = catalog.definition(pack.id), let small = catalog.definition(base.id),
        let bigPrice = Double(big.price), let smallPrice = Double(small.price), smallPrice > 0,
        bigPrice > 0
      else { return nil }
      let rate = Double(big.stamps) / bigPrice
      let baseRate = Double(small.stamps) / smallPrice
      return Int(((rate / baseRate - 1) * 100).rounded())
    }

    private var statusLine: String? {
      switch model.status {
      case .idle, .buying: nil
      case .waiting: "Waiting for approval. The coins arrive once it's given."
      case .delivering: "Paid. Your coins arrive as soon as Ourio reaches its server."
      case .bought(let coins): "+\(coins) coins. Enjoy!"
      case .failed(let error): CoinPacksModel.message(error)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
      Card(state: isFit ? .selected : .rest) {
        // At accessibility sizes the pile gives its room to the count, and the price button takes the row.
        if typeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: Space.m) {
            details
            button.frame(maxWidth: .infinity)
          }
        } else {
          HStack(spacing: Space.m) {
            CoinPile(rows: PackStore.piles[tier])
              .frame(width: CoinPile.width)
            details
            Spacer(minLength: 0)
            button
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(isFit ? "fitPack" : pack.id)
    }

    private var details: some View {
      VStack(alignment: .leading, spacing: Space.xs) {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
          Text(pack.stamps.formatted())
            .font(.ourioTitleDigits)
            .foregroundStyle(Ink.text)
            .fixedSize()
          Text("coins")
            .font(.ourioCallout)
            .foregroundStyle(Ink.textSecondary)
            .fixedSize()
        }
        if isFit {
          Chip("Covers what you need", symbol: "checkmark", style: .honey)
        } else if let badge {
          Chip(badge, style: .honey)
        }
      }
    }

    private var button: some View {
      Button(action: buy) {
        if buying {
          ProgressView().tint(Ink.heroInk)
        } else {
          Text(pack.displayPrice).monospacedDigit().lineLimit(1).fixedSize()
        }
      }
      .buttonStyle(PrimaryButtonStyle(fullWidth: typeSize.isAccessibilitySize))
      .disabled(locked)
      .accessibilityLabel("Buy \(pack.stamps) coins for \(pack.displayPrice)")
    }
  }

  /// Coins heaped in a pyramid: `rows` is how many sit in each row, bottom first.
  private struct CoinPile: View {
    let rows: [Int]

    private static let coin: CGFloat = 20
    /// The widest row, four coins overlapping.
    static let width: CGFloat = coin * 4 - 5 * 3

    var body: some View {
      VStack(spacing: -8) {
        ForEach(Array(rows.reversed().enumerated()), id: \.offset) { _, count in
          HStack(spacing: -5) {
            ForEach(0..<count, id: \.self) { _ in
              CoinIcon(size: Self.coin)
            }
          }
        }
      }
      .accessibilityHidden(true)
    }
  }
#endif
