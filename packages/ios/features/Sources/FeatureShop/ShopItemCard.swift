#if canImport(UIKit)
  import DecorInterface
  import Design
  import SwiftUI
  import WidgetUI

  /// An `ItemCard`: the art and one-line name open the item's sheet; the price under them is the tile's only button.
  /// Every tile has the same parts, so a row is level whatever each one costs or whether it is owned.
  struct ShopItemCard: View {
    let item: ShopItem
    let state: any ShopHost
    var onTap: () -> Void

    @State private var shortTaps = 0

    private var owned: Bool { state.shop.owned.contains(item.id) }
    private var standing: ShopPriceFace.Standing {
      guard DecorItem.item(shopID: item.id) != nil else { return .notPlaceable }
      return state.isPlaced(item.id) ? .room : .closet
    }
    private var price: Int { state.shop.price(of: item) }
    private var isDeal: Bool { price < item.price }
    private var face: ShopPriceFace {
      ShopPriceFace(
        price: price, was: item.price, coins: state.shop.coins, owned: owned, standing: standing)
    }

    var body: some View {
      ItemCard(item.name, tag: ItemTag(item.rarity.title, color: item.rarity.tint), open: onTap) {
        art
      } leadingBadge: {
        if isDeal, !owned {
          Chip(
            "−\(Int(((1 - Double(price) / Double(item.price)) * 100).rounded()))%", style: .honey)
        } else if item.isNew, !owned {
          Chip("New", style: .honey)
        }
      } trailingBadge: {
        EmptyView()
      } footer: {
        TileButton(face.tileFace, name: item.name) {
          switch face.tap {
          case .buy: _ = state.shop.buy(item)
          case .askForCoins:
            shortTaps += 1
            _ = state.shop.buy(item)
          case .place: state.decorate(item.id)
          case .none: break
          }
        }
        .haptic(.warning, trigger: shortTaps)
      }
      .perfFlattened()
    }

    private var art: some View {
      RarityFrame(rarity: item.rarity) {
        if let image = Thumbnails.image(item.thumbnail, maxPixels: 512) {
          // The thumbnail carries its own soft shadow; nothing is drawn under it.
          // An owned piece's art steps back; its name stays in full ink.
          Image(uiImage: image).resizable().scaledToFit()
            .padding(Space.s)
            .opacity(owned ? 0.6 : 1)
        } else {
          Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(Ink.textTertiary)
        }
      }
    }
  }
#endif
