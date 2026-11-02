import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The Shop tab: the scene's 3D shop with the keeper behind the counter. Tapping something for
/// sale opens the shop sheet on it, where it is bought with stamps and goes to the closet.
///
/// The sheet stops at half height first, so the keeper can be seen answering a purchase.
struct ShopTab: View {
  private enum Sheet: Identifiable {
    case item(ShopItem.ID)
    case closet

    var id: String {
      switch self {
      case .item(let id): "item-\(id)"
      case .closet: "closet"
      }
    }
  }

  let shop: ShopStore
  let renovator: RoomRenovator
  let scene: any PetScene
  let keeper: Shopkeeper
  /// Shows Home, where a piece taken from the closet is placed.
  let onShowRoom: () -> Void

  @State private var sheet: Sheet?
  @State private var purchases = 0

  private var state: ShopSceneState {
    ShopSceneState(items: shop.catalog.items, keeper: keeper, purchases: purchases)
  }

  var body: some View {
    ZStack(alignment: .top) {
      scene.makeShopScene(state: state) { event in
        switch event {
        case .picked(let id): sheet = .item(id)
        }
      }
      controls
    }
    // Stamps only go down when something is bought.
    .onChange(of: shop.stamps) { old, new in
      if new < old { purchases += 1 }
    }
    .onChange(of: renovator.placements) {
      sheet = nil
      onShowRoom()
    }
    .sheet(item: $sheet) { sheet in
      switch sheet {
      case .item(let id):
        ShopView(
          store: shop, item: id, onOpenCloset: { self.sheet = .closet },
          onClose: { self.sheet = nil }
        ) { item in
          scene.makeShopPreview(item: item) ?? AnyView(EmptyView())
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
      case .closet:
        ClosetView(
          store: shop, renovator: renovator,
          onOpenShop: { self.sheet = .item(shop.catalog.items.first?.id ?? "") },
          onClose: { self.sheet = nil }
        )
        .presentationDetents([.medium, .large])
      }
    }
  }

  private var controls: some View {
    HStack(spacing: Spacing.small) {
      StampPlate(balance: shop.stamps)
      Spacer(minLength: Spacing.small)
      GlassGroup {
        IconButton("archivebox.fill", label: "Closet") { sheet = .closet }
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.small)
  }
}
