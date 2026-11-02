import DesignSystem
import Pet
import SwiftUI

/// A box tied with a ribbon. Open, its flaps are folded back and the cat's ears show over the rim.
struct GiftBoxArt: View {
  let open: Bool

  var body: some View {
    ZStack(alignment: .bottom) {
      if open {
        HStack(spacing: 14) {
          Triangle().fill(Palette.woodLit.color).frame(width: 10, height: 12)
          Triangle().fill(Palette.woodLit.color).frame(width: 10, height: 12)
        }
        .offset(y: -22)
      }
      RoundedRectangle(cornerRadius: 4)
        .fill(Palette.clay.color)
        .frame(width: 40, height: 28)
      Rectangle().fill(Palette.paperTurned.color).frame(width: 7, height: 28)
      RoundedRectangle(cornerRadius: 3)
        .fill(Palette.clayLit.color)
        .frame(width: 44, height: open ? 5 : 9)
        .offset(y: open ? -26 : -24)
    }
    .frame(width: 48, height: 52)
    .accessibilityHidden(true)
  }

  private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.closeSubpath()
      return path
    }
  }
}

/// Home's rows for gifts: wrapped ones on the doormat to open, the ones this phone sent, and a way
/// to wrap something from the closet. No money is involved: an item only moves from one closet
/// to the other.
public struct GiftSection: View {
  private let gifts: GiftBoxStore
  private let shop: ShopStore
  private let catName: String?
  private let onWrap: (ShopItem) -> Void
  private let onUnwrap: (UUID) -> Void

  public init(
    gifts: GiftBoxStore, shop: ShopStore, catName: String?, onWrap: @escaping (ShopItem) -> Void,
    onUnwrap: @escaping (UUID) -> Void
  ) {
    self.gifts = gifts
    self.shop = shop
    self.catName = catName
    self.onWrap = onWrap
    self.onUnwrap = onUnwrap
  }

  private var giftable: [ShopItem] {
    shop.catalog.items.filter { !$0.ownsAtMostOne && shop.owned($0) > 0 }
  }

  public var body: some View {
    VStack(spacing: Spacing.small) {
      ForEach(gifts.box.gifts) { gift in
        row(gift)
      }
      wrapRow
    }
    .calmAnimation(value: gifts.box.gifts.map(\.id))
    .accessibilityIdentifier("gifts")
  }

  private func name(_ gift: Gift) -> String {
    shop.catalog.item(gift.itemID)?.name ?? "something"
  }

  @ViewBuilder private func row(_ gift: Gift) -> some View {
    switch (gift.direction, gift.state) {
    case (.incoming, .wrapped):
      ListRow(
        "A wrapped gift is on the doormat",
        subtitle: "\(catName ?? "The cat") is eyeing the box."
      ) {
        GiftBoxArt(open: false)
      } trailing: {
        Button("Unwrap") { onUnwrap(gift.id) }
          .billetType(.action)
          .foregroundStyle(Palette.gold.color)
          .frame(minWidth: Target.minimum, minHeight: Target.minimum)
      }
      .card()
    case (.incoming, .opened):
      ListRow(
        "\(name(gift)) is in your closet",
        subtitle: gift.id == gifts.lastUnwrapped
          ? "\(catName ?? "The cat") is already sitting in the box." : "From your partner."
      ) {
        GiftBoxArt(open: true)
      } trailing: {
        EmptyView()
      }
      .card()
    case (.outgoing, .wrapped):
      ListRow("Your gift is on their doormat", subtitle: "\(name(gift)), wrapped.") {
        GiftBoxArt(open: false)
      } trailing: {
        EmptyView()
      }
      .card()
    case (.outgoing, .opened):
      ListRow("Your partner unwrapped \(name(gift))", subtitle: "The box is theirs now.") {
        GiftBoxArt(open: true)
      } trailing: {
        EmptyView()
      }
      .card()
    }
  }

  private var wrapRow: some View {
    ListRow(
      "Wrap something",
      subtitle: giftable.isEmpty
        ? "Your closet has nothing to wrap yet."
        : "It leaves your closet and lands on their doormat."
    ) {
      EmptyView()
    } trailing: {
      Menu("Choose") {
        ForEach(giftable) { item in
          Button("\(item.name) (\(shop.owned(item)))") { onWrap(item) }
        }
      }
      .billetType(.action)
      .tint(Palette.gold.color)
      .disabled(giftable.isEmpty)
      .frame(minWidth: Target.minimum, minHeight: Target.minimum)
    }
    .card()
  }
}
