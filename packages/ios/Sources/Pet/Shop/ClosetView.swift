import DesignSystem
import SwiftUI

/// The closet: what the pair owns, by category, and what to do with each thing.
///
/// Furniture and materials go to the room through ``RoomRenovating``. A treat is used up here, and
/// the store counts the use so the scene can react.
public struct ClosetView: View {
  private let store: ShopStore
  private let renovator: any RoomRenovating
  private let onOpenShop: () -> Void
  private let onClose: () -> Void

  @State private var used = 0
  @State private var refusal: String?

  public init(
    store: ShopStore,
    renovator: any RoomRenovating,
    onOpenShop: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.store = store
    self.renovator = renovator
    self.onOpenShop = onOpenShop
    self.onClose = onClose
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      VStack(spacing: Spacing.small) {
        header
        if isEmpty {
          Spacer()
          EmptyWire(
            title: "The closet is empty",
            message: "What you buy in the shop waits here until you use it.")
          BilletButton("Open the shop", rank: .primary, action: onOpenShop)
            .padding(.horizontal, Spacing.wide)
          Spacer()
        } else {
          list
        }
      }
    }
    .sensoryFeedback(.impact(flexibility: .soft), trigger: used)
  }

  private var isEmpty: Bool {
    store.state.closet.isEmpty && store.state.layout.placements.isEmpty
  }

  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.small) {
        closetTitle
        Spacer(minLength: Spacing.small)
        IconButton("bag.fill", label: "Shop", action: onOpenShop)
        IconButton("xmark", label: "Close", action: onClose)
      }
      VStack(alignment: .leading, spacing: Spacing.small) {
        closetTitle
        HStack(spacing: Spacing.small) {
          IconButton("bag.fill", label: "Shop", action: onOpenShop)
          IconButton("xmark", label: "Close", action: onClose)
        }
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.small)
  }

  private var closetTitle: some View {
    Text("Closet")
      .billetType(.title)
      .foregroundStyle(Palette.paper.color)
      .accessibilityAddTraits(.isHeader)
  }

  private var list: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.large) {
        ForEach(ShopItem.Category.shelves, id: \.self) { category in
          let owned = ownedItems(in: category)
          let placed = placedItems(in: category)
          if !owned.isEmpty || !placed.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.small) {
              Text(category.title)
                .billetType(.heading)
                .foregroundStyle(Palette.paper.color)
                .accessibilityAddTraits(.isHeader)
              ForEach(owned) { item in ownedRow(item) }
              ForEach(placed, id: \.placement.id) { entry in placedRow(entry.item, entry.placement)
              }
            }
          }
        }
        if let refusal {
          Text(refusal)
            .billetType(.label)
            .foregroundStyle(Palette.clayLit.color)
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.large)
      .calmAnimation(value: store.state)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private func ownedItems(in category: ShopItem.Category) -> [ShopItem] {
    store.catalog.items(in: category).filter { store.owned($0) > 0 }
  }

  private func placedItems(
    in category: ShopItem.Category
  ) -> [(item: ShopItem, placement: RoomLayout.Placement)] {
    store.state.layout.placements.compactMap { placement in
      guard let item = store.catalog.item(placement.item), item.category == category else {
        return nil
      }
      return (item, placement)
    }
  }

  private func ownedRow(_ item: ShopItem) -> some View {
    let count = store.owned(item)
    return ListRow(
      item.name, subtitle: count > 1 ? "\(count) in the closet" : usedOnText(item)
    ) {
      RowIcon(item.symbol, color: item.tint)
    } trailing: {
      BilletButton(actionTitle(item), rank: .secondary) { use(item) }
        .fixedSize()
    }
    .card()
  }

  private func placedRow(_ item: ShopItem, _ placement: RoomLayout.Placement) -> some View {
    ListRow(item.name, subtitle: "In the room") {
      RowIcon(item.symbol, color: item.tint)
    } trailing: {
      BilletButton("Put away", rank: .secondary) {
        attempt { try renovator.renovate(.putAway(placement: placement.id)) }
      }
      .fixedSize()
    }
    .card()
  }

  private func usedOnText(_ item: ShopItem) -> String {
    guard case .material(let surface, _) = item.look,
      store.state.layout.material(on: surface) == item.id
    else { return item.detail }
    return surface == .wall ? "On the walls" : "On the floor"
  }

  private func actionTitle(_ item: ShopItem) -> String {
    switch item.look {
    case .furniture: "Place"
    case .material: "Use"
    case .treat: "Give"
    case .style: "Use"
    }
  }

  private func use(_ item: ShopItem) {
    switch item.look {
    case .furniture:
      attempt { try renovator.renovate(.place(item)) }
    case .material:
      attempt { try renovator.renovate(.paint(item)) }
    case .treat:
      attempt {
        try store.use(item, transaction: store.newTransaction())
        used += 1
      }
    case .style:
      // Styles are chosen in the Style tab; the closet never lists them.
      break
    }
  }

  private func attempt(_ body: () throws -> Void) {
    do {
      try body()
      refusal = nil
    } catch let error as ShopError {
      refusal = Self.message(for: error)
    } catch {
      refusal = "That didn't work."
    }
  }

  private static func message(for error: ShopError) -> String {
    switch error {
    case .roomIsFull: "There is no free spot left in the room."
    case .notInCloset: "That is not in the closet."
    case .unknownItem, .notEnoughStamps, .alreadyOwned, .wrongKind, .unknownPlacement:
      "That didn't work."
    }
  }
}
