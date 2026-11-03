import DesignSystem
import Pet
import PetScene
import SwiftUI

/// Adds the closet to Home when the chosen scene can draw what it holds. The closet can still
/// open the shop; the Shop tab is the usual way in.
///
/// Neither screen is built until it is opened, so a scene without a shop pays nothing.
struct HomeShop: ViewModifier {
  enum Sheet: Identifiable {
    case shop
    case closet

    var id: Self { self }
  }

  let shop: ShopStore
  let renovator: RoomRenovator
  let scene: (any PetScene)?
  /// False when Home opens the shop and the closet from somewhere else.
  var showsButtons = true
  @Binding var sheet: Sheet?

  private var isAvailable: Bool { scene?.hasShop ?? false }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .topTrailing) {
        if isAvailable, showsButtons {
          GlassGroup {
            HStack(spacing: Spacing.small) {
              IconButton("archivebox.fill", label: "Closet") { sheet = .closet }
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
