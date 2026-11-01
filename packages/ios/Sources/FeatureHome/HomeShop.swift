import DesignSystem
import Pet
import PetScene
import SwiftUI

/// Adds the shop and the closet to Home when the chosen scene can draw what they hold.
///
/// Neither screen is built until it is opened, so a scene without a shop pays nothing.
struct HomeShop: ViewModifier {
  private enum Sheet: Identifiable {
    case shop
    case closet

    var id: Self { self }
  }

  let shop: ShopStore
  let renovator: RoomRenovator
  let scene: (any PetScene)?

  @State private var sheet: Sheet?

  private var isAvailable: Bool { scene?.hasShop ?? false }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .topTrailing) {
        if isAvailable {
          GlassGroup {
            HStack(spacing: Spacing.small) {
              IconButton("archivebox.fill", label: "Closet") { sheet = .closet }
              IconButton("bag.fill", label: "Shop") { sheet = .shop }
            }
          }
          .padding(.top, Spacing.small)
          .padding(.trailing, Spacing.medium)
          .transition(.opacity)
        }
      }
      // A placed piece is moved in the room itself, so the closet gets out of the way.
      .onChange(of: renovator.placements) { sheet = nil }
      .sheet(item: isAvailable ? $sheet : .constant(nil)) { sheet in
        switch sheet {
        case .shop:
          ShopView(
            store: shop, onOpenCloset: { self.sheet = .closet }, onClose: { self.sheet = nil }
          ) { item in
            scene?.makeShopPreview(item: item) ?? AnyView(EmptyView())
          }
          .presentationDetents([.large])
        case .closet:
          ClosetView(
            store: shop, renovator: renovator,
            onOpenShop: { self.sheet = .shop }, onClose: { self.sheet = nil }
          )
          // The room stays in view and live, so the cat can be seen reacting to a treat.
          .presentationDetents([.medium, .large])
          .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
      }
  }
}
