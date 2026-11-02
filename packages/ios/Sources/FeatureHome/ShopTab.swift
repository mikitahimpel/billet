import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The Shop tab: the scene's 3D shop with the keeper behind the counter. Everything on the shelves,
/// the counter and the table carries a price tag. Tapping one brings it forward with a button to
/// get it for its stamps; the keeper hands it over and it goes to the closet.
///
/// The first visit shows one short hint, until something is tapped.
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
  @State private var focused: ShopItem.ID?
  @State private var transactions: [ShopItem.ID: String] = [:]
  @State private var bought: ShopItem?
  @State private var showsHint = false
  @AppStorage("shop.hintSeen") private var hintSeen = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var owned: Set<ShopItem.ID> {
    Set(shop.catalog.items.filter { $0.ownsAtMostOne && shop.owned($0) > 0 }.map(\.id))
  }

  private var state: ShopSceneState {
    ShopSceneState(
      items: shop.catalog.items, keeper: keeper, purchases: purchases, focused: focused,
      owned: owned)
  }

  var body: some View {
    ZStack(alignment: .top) {
      scene.makeShopScene(state: state) { event in
        switch event {
        case .picked(let id): pick(id)
        }
      }
      controls
      if showsHint { hint.transition(.opacity.combined(with: .move(edge: .top))) }
    }
    .overlay(alignment: .bottom) {
      VStack(spacing: Spacing.small) {
        if let bought { BoughtToast(item: bought) { sheet = .closet } }
        if let item = focused.flatMap(shop.catalog.item) {
          ShopOffer(
            item: item, stamps: shop.stamps, owned: shop.owned(item),
            onGet: { get(item) }, onDetails: { sheet = .item(item.id) },
            onClose: { setFocus(nil) }
          )
          .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      .padding(.horizontal, Spacing.medium)
      .padding(.bottom, Spacing.small)
    }
    // Stamps only go down when something is bought.
    .onChange(of: shop.stamps) { old, new in
      if new < old { purchases += 1 }
    }
    .onChange(of: renovator.placements) {
      sheet = nil
      onShowRoom()
    }
    .task {
      guard !hintSeen else { return }
      try? await Task.sleep(for: .seconds(1.6))
      guard !hintSeen else { return }
      withAnimation(reduceMotion ? nil : Motion.spring) { showsHint = true }
      try? await Task.sleep(for: .seconds(6))
      dismissHint()
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
      case .closet:
        ClosetView(
          store: shop, renovator: renovator,
          onOpenShop: { self.sheet = nil },
          onClose: { self.sheet = nil }
        )
        .presentationDetents([.medium, .large])
      }
    }
    .sensoryFeedback(.success, trigger: purchases)
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

  private var hint: some View {
    HStack(spacing: Spacing.small) {
      Image(systemName: "hand.tap.fill")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(Palette.gold.color)
        .symbolEffect(.bounce, options: .repeat(3), isActive: !reduceMotion)
      Text("Tap anything with a price tag to buy it")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small + 2)
    .background(Palette.plate.color.opacity(0.82), in: .capsule)
    .padding(.top, 64)
    .onTapGesture { dismissHint() }
    .accessibilityAddTraits(.isStaticText)
  }

  private func pick(_ id: ShopItem.ID) {
    dismissHint()
    bought = nil
    setFocus(id)
  }

  private func setFocus(_ id: ShopItem.ID?) {
    withAnimation(reduceMotion ? nil : Motion.spring) { focused = id }
  }

  private func dismissHint() {
    hintSeen = true
    guard showsHint else { return }
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { showsHint = false }
  }

  private func get(_ item: ShopItem) {
    let transaction = transactions[item.id] ?? shop.newTransaction()
    transactions[item.id] = transaction
    do {
      let outcome = try shop.buy(item, transaction: transaction)
      transactions[item.id] = nil
      guard outcome == .applied else { return }
      setFocus(nil)
      withAnimation(reduceMotion ? nil : Motion.spring) { bought = item }
      Task {
        try? await Task.sleep(for: .seconds(4))
        if bought?.id == item.id {
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { bought = nil }
        }
      }
    } catch {
      // A refused buy has not used its transaction, so the next tap may succeed with the same one.
    }
  }
}

/// The item brought forward: its name, what it is for, and the button to get it for its stamps.
private struct ShopOffer: View {
  let item: ShopItem
  let stamps: Int
  let owned: Int
  let onGet: () -> Void
  let onDetails: () -> Void
  let onClose: () -> Void

  private var isOwned: Bool { item.ownsAtMostOne && owned > 0 }
  private var shortBy: Int { max(item.price - stamps, 0) }

  private var purpose: String {
    switch item.look {
    case .furniture: "For your room"
    case .treat: "A treat for your cat"
    case .material(let surface, _):
      switch surface {
      case .wall: "Paint for your walls"
      case .floor: "Boards for your floor"
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small + 4) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
          Text(owned > 0 && !isOwned ? "\(purpose) · \(owned) in your closet" : purpose)
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
        }
        Spacer(minLength: Spacing.small)
        Button("Details", action: onDetails)
          .billetType(.label)
          .foregroundStyle(Palette.light.color)
        IconButton("xmark", label: "Close", action: onClose)
      }
      Button(action: onGet) {
        ButtonLabel(title, rank: .primary, systemImage: isOwned ? "checkmark" : "seal.fill")
          .frame(maxWidth: .infinity)
      }
      .billetButton(.primary)
      .disabled(isOwned || shortBy > 0)
      .accessibilityLabel(
        isOwned ? "\(item.name), owned" : "Get \(item.name) for \(item.price) stamps")
      if shortBy > 0, !isOwned {
        Text("You need \(shortBy) more stamps. Send notes to earn them.")
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
    }
    .padding(Spacing.medium)
    .background(Palette.plate.color.opacity(0.9), in: .rect(cornerRadius: 24))
  }

  private var title: String {
    isOwned ? "Owned" : "Get for \(item.price) stamps"
  }
}

/// A short note that something bought went to the closet, with the way there.
private struct BoughtToast: View {
  let item: ShopItem
  let onOpenCloset: () -> Void

  var body: some View {
    HStack(spacing: Spacing.small) {
      Image(systemName: "gift.fill")
        .foregroundStyle(Palette.gold.color)
      Text("\(item.name) is in your closet")
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
      Spacer(minLength: Spacing.small)
      Button("Open closet", action: onOpenCloset)
        .billetType(.label)
        .foregroundStyle(Palette.light.color)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small + 4)
    .background(Palette.plate.color.opacity(0.9), in: .capsule)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}
