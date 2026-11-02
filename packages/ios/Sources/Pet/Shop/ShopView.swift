import DesignSystem
import SwiftUI

/// Names of the coordinate spaces the shop measures in.
private enum ShopSpace {
  static let screen = "shop"
  static let content = "shopContent"
}

/// The shop: three sections of cards, the stamps in the wallet, and the way to the closet.
///
/// Only the selected card shows a live preview, and there is one preview view for the whole
/// screen. It sits over the selected card and slides to the next one, so choosing another item
/// swaps the model in the same renderer instead of starting another.
public struct ShopView<Preview: View>: View {

  private struct Flight: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Swatch
    let from: CGPoint
  }

  private let store: ShopStore
  private let onClose: () -> Void
  private let onOpenCloset: () -> Void
  private let preview: (ShopItem) -> Preview

  @State private var selected: ShopItem.ID?
  @State private var slots: [ShopItem.ID: CGRect] = [:]
  @State private var transactions: [ShopItem.ID: String] = [:]
  @State private var flights: [Flight] = []
  @State private var closetCentre = CGPoint.zero
  @State private var scrollTop: CGFloat = 0
  @State private var scrollOffset = ScrollBox()
  @State private var bought = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    store: ShopStore,
    onOpenCloset: @escaping () -> Void,
    onClose: @escaping () -> Void,
    @ViewBuilder preview: @escaping (ShopItem) -> Preview
  ) {
    self.store = store
    self.onOpenCloset = onOpenCloset
    self.onClose = onClose
    self.preview = preview
    _selected = State(initialValue: store.catalog.items.first?.id)
  }

  public var body: some View {
    ZStack {
      EveningBackground()
      VStack(spacing: Spacing.small) {
        header
        shelves
      }
      ForEach(flights) { flight in
        FlyingItem(symbol: flight.symbol, tint: flight.tint, from: flight.from, to: closetCentre)
      }
    }
    .coordinateSpace(name: ShopSpace.screen)
    .sensoryFeedback(.success, trigger: bought)
  }

  private var header: some View {
    HStack(spacing: Spacing.small) {
      Text("Shop")
        .billetType(.title)
        .foregroundStyle(Palette.paper.color)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: Spacing.small)
      StampPlate(balance: store.stamps)
      IconButton("archivebox.fill", label: "Closet", action: onOpenCloset)
        .overlay(alignment: .topTrailing) { closetBadge }
        .symbolEffect(.bounce, value: bought)
        .onGeometryChange(for: CGPoint.self) {
          let frame = $0.frame(in: .named(ShopSpace.screen))
          return CGPoint(x: frame.midX, y: frame.midY)
        } action: {
          closetCentre = $0
        }
      IconButton("xmark", label: "Close", action: onClose)
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.top, Spacing.small)
  }

  @ViewBuilder private var closetBadge: some View {
    let count = store.state.closet.counts.values.reduce(0, +)
    if count > 0 {
      Text(verbatim: "\(count)")
        .billetType(.label)
        .foregroundStyle(Palette.ink.color)
        .padding(.horizontal, Spacing.small - 2)
        .background(Palette.gold.color, in: .capsule)
        .contentTransition(.numericText(value: Double(count)))
        .calmAnimation(value: count)
        .offset(x: 4, y: -4)
        .accessibilityHidden(true)
    }
  }

  private var shelves: some View {
    ScrollView {
      ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: Spacing.large) {
          ForEach(ShopItem.Category.allCases, id: \.self) { category in
            section(category)
          }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.large)
        if let item = selectedItem, let slot = slots[item.id] {
          preview(item)
            .frame(width: slot.width, height: slot.height)
            .offset(x: slot.minX, y: slot.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .coordinateSpace(name: ShopSpace.content)
    }
    .scrollBounceBehavior(.basedOnSize)
    .onScrollGeometryChange(for: CGFloat.self) {
      $0.contentOffset.y + $0.contentInsets.top
    } action: { _, offset in
      scrollOffset.value = offset
    }
    .onGeometryChange(for: CGFloat.self) {
      $0.frame(in: .named(ShopSpace.screen)).minY
    } action: {
      scrollTop = $0
    }
  }

  private var selectedItem: ShopItem? {
    selected.flatMap { store.catalog.item($0) }
  }

  private func section(_ category: ShopItem.Category) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      VStack(alignment: .leading, spacing: 0) {
        Text(category.title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        Text(category.subtitle)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: Spacing.small), GridItem(.flexible())],
        spacing: Spacing.small
      ) {
        ForEach(store.catalog.items(in: category)) { item in
          card(item)
        }
      }
    }
  }

  private func card(_ item: ShopItem) -> some View {
    let isSelected = item.id == selected
    return VStack(alignment: .leading, spacing: Spacing.small) {
      ZStack {
        ShopItemGlyph(item: item)
          .opacity(isSelected ? 0 : 1)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 120)
      .background(Palette.plate.color.opacity(0.6), in: .rect(cornerRadius: Radius.plate))
      .overlay(alignment: .topTrailing) {
        let owned = store.owned(item)
        if owned > 0 {
          Text(verbatim: "×\(owned)")
            .billetType(.label)
            .foregroundStyle(Palette.gold.color)
            .padding(Spacing.small)
            .accessibilityLabel("\(owned) in the closet")
        }
      }
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(ShopSpace.content))
      } action: {
        slots[item.id] = $0
      }
      VStack(alignment: .leading, spacing: 0) {
        Text(item.name)
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        Text(item.detail)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .lineLimit(1)
      }
      buyButton(item)
    }
    .padding(Spacing.small)
    .card()
    .overlay {
      if isSelected {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
          .strokeBorder(Palette.gold.color.opacity(0.7), lineWidth: 1.5)
      }
    }
    .contentShape(.rect)
    .onTapGesture { select(item) }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder private func buyButton(_ item: ShopItem) -> some View {
    let isOwned = item.ownsAtMostOne && store.owned(item) > 0
    let canAfford = store.stamps >= item.price
    Button {
      buy(item)
    } label: {
      ButtonLabel(
        isOwned ? "Owned" : "\(item.price)", rank: .primary,
        systemImage: isOwned ? "checkmark" : "seal.fill")
    }
    .billetButton(.primary)
    .disabled(isOwned || !canAfford)
    .accessibilityLabel(
      isOwned ? "\(item.name), owned" : "Buy \(item.name) for \(item.price) stamps")
  }

  private func select(_ item: ShopItem) {
    guard item.id != selected else { return }
    withAnimation(reduceMotion ? nil : Motion.spring) { selected = item.id }
  }

  private func buy(_ item: ShopItem) {
    let transaction = transactions[item.id] ?? store.newTransaction()
    transactions[item.id] = transaction
    do {
      let outcome = try store.buy(item, transaction: transaction)
      transactions[item.id] = nil
      guard outcome == .applied else { return }
      bought += 1
      launch(item)
    } catch {
      // A refused buy has not used its transaction, so the next tap may succeed with the same one.
    }
  }

  /// Sends the item's glyph from its card to the closet.
  private func launch(_ item: ShopItem) {
    guard !reduceMotion, let slot = slots[item.id] else { return }
    let from = CGPoint(
      x: slot.midX, y: slot.midY - scrollOffset.value + scrollTop)
    let flight = Flight(symbol: item.symbol, tint: item.tint, from: from)
    flights.append(flight)
    Task {
      try? await Task.sleep(for: .seconds(0.9))
      flights.removeAll { $0.id == flight.id }
    }
  }
}

/// The flat picture of an item, for a card with no live preview over it.
public struct ShopItemGlyph: View {
  private let item: ShopItem

  public init(item: ShopItem) {
    self.item = item
  }

  public var body: some View {
    Image(systemName: item.symbol)
      .font(.system(size: 40))
      .foregroundStyle(item.tint.color)
  }
}

/// Holds the scroll position without making the screen redraw as it changes.
private final class ScrollBox {
  var value: CGFloat = 0
}

private struct FlyingItem: View {
  let symbol: String
  let tint: Swatch
  let from: CGPoint
  let to: CGPoint

  @State private var landed = false

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 28))
      .foregroundStyle(tint.color)
      .frame(width: 56, height: 56)
      .background(Palette.plate.color, in: .circle)
      .lampGlow()
      .scaleEffect(landed ? 0.35 : 1)
      .opacity(landed ? 0 : 1)
      .position(landed ? to : from)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .onAppear {
        withAnimation(.timingCurve(0.3, 0.1, 0.2, 1, duration: 0.75)) { landed = true }
      }
  }
}

/// The wallet balance, as a plate with a stamp.
public struct StampPlate: View {
  private let balance: Int

  public init(balance: Int) {
    self.balance = balance
  }

  public var body: some View {
    HStack(spacing: Spacing.hair) {
      Image(systemName: "seal.fill")
        .font(IconStyle.font)
      Text(verbatim: "\(balance)")
        .billetType(.numeral)
        .contentTransition(.numericText(value: Double(balance)))
    }
    .foregroundStyle(Palette.gold.color)
    .padding(.horizontal, Spacing.small)
    .frame(minHeight: Target.minimum)
    .background(Palette.plate.color, in: .capsule)
    .calmAnimation(value: balance)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(balance) stamps")
  }
}
