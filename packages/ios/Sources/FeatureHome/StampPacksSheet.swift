import DesignSystem
import Payments
import Pet
import SwiftUI

/// The stamp packs for sale, one row each with its price, and the wallet balance on top. The shop
/// presents it (or restyles it); it only needs a ``StampShop`` and the pair's ``ShopStore``.
public struct StampPacksSheet: View {
  private let stampShop: StampShop
  private let shop: ShopStore

  public init(stampShop: StampShop, shop: ShopStore) {
    self.stampShop = stampShop
    self.shop = shop
  }

  public var body: some View {
    SheetPanel("Get stamps") {
      HStack {
        Text("Your stamps")
          .billetType(.body)
          .foregroundStyle(Palette.muted.color)
        Spacer()
        StampPlate(balance: shop.stamps)
          .accessibilityIdentifier("stampPacks.balance")
      }
      SettingsGroup {
        ForEach(stampShop.packs) { pack in
          if pack.id != stampShop.packs.first?.id { ListDivider() }
          row(pack)
        }
      }
      status
    }
    .task { await stampShop.load() }
    .sensoryFeedback(.success, trigger: boughtCount)
  }

  private var boughtCount: Int {
    if case .bought(let credit) = stampShop.state { return credit.transactionID.hashValue }
    return 0
  }

  private func row(_ pack: StampPack) -> some View {
    HStack(spacing: Spacing.small) {
      Image(systemName: "seal.fill")
        .font(IconStyle.font)
        .foregroundStyle(Palette.gold.color)
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(pack.displayName)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        Text(pack.description)
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
      Spacer(minLength: Spacing.small)
      Button {
        Task { await stampShop.buy(pack) }
      } label: {
        if stampShop.state == .buying(pack.id) {
          ProgressView()
        } else {
          Text(pack.displayPrice)
        }
      }
      .billetButton(.primary)
      .disabled(stampShop.isBuying)
      .accessibilityLabel("Buy \(pack.displayName) for \(pack.displayPrice)")
      .accessibilityIdentifier("stampPacks.buy.\(pack.stamps)")
    }
    .padding(Spacing.medium)
  }

  @ViewBuilder private var status: some View {
    switch stampShop.state {
    case .idle, .buying:
      EmptyView()
    case .loading:
      ProgressView().frame(maxWidth: .infinity)
    case .pending:
      note("Waiting for approval. The stamps arrive once it's approved.")
    case .bought(let credit):
      note("+\(credit.stamps) stamps. Thank you!")
        .accessibilityIdentifier("stampPacks.bought")
    case .failed(let message):
      note(message)
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .billetType(.caption)
      .foregroundStyle(Palette.muted.color)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
