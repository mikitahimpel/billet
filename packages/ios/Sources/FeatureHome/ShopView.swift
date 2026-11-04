import CoreGraphics
import DesignSystem
import Pet
import SwiftUI

/// The shop: a grid of cards on four shelves (furniture, decor, window views and things for the
/// cat), each with a picture and its price. Tapping the price buys it at once; for a few seconds
/// the purchase can be taken back. A long press looks closer, and tries a window view on.
///
/// In a tab it has the evening behind it; in a sheet (``View/billetSheet(_:)``) the sheet's ground.
struct ShopView: View {
  /// Makes a still picture of an item, `side` points square at `scale` pixels a point.
  typealias Thumbnail =
    @MainActor (ShopItem, _ side: CGFloat, _ scale: CGFloat) async ->
    CGImage?

  /// What the strip at the foot says.
  private enum Notice: Equatable {
    case bought(ShopCheckout.Receipt)
    case short(ShopItem, by: Int)
  }

  private let store: ShopStore
  private let checkout: ShopCheckout
  private let style: RoomStyle
  private let thumbnail: Thumbnail
  private let onPlace: (ShopItem) -> Void
  private let onTryOn: ((RoomStyleItem) -> Void)?
  private let onOpenCloset: () -> Void
  private let onClose: (() -> Void)?

  @State private var notice: Notice?
  @State private var purchases = 0
  @State private var popped: ShopItem.ID?
  @Environment(\.isInSheet) private var isInSheet
  @Environment(\.appEvents) private var events
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize

  /// - Parameters:
  ///   - style: How the room is done up now, so a view in use says so.
  ///   - onPlace: Shows the room with `item` from the closet ready to be placed.
  ///   - onTryOn: Shows the room with a window view tried on; `nil` when there is no room to try
  ///     it in.
  ///   - onClose: Closes the shop, in a sheet.
  init(
    store: ShopStore,
    checkout: ShopCheckout,
    style: RoomStyle,
    thumbnail: @escaping Thumbnail,
    onPlace: @escaping (ShopItem) -> Void,
    onTryOn: ((RoomStyleItem) -> Void)?,
    onOpenCloset: @escaping () -> Void,
    onClose: (() -> Void)? = nil
  ) {
    self.store = store
    self.checkout = checkout
    self.style = style
    self.thumbnail = thumbnail
    self.onPlace = onPlace
    self.onTryOn = onTryOn
    self.onOpenCloset = onOpenCloset
    self.onClose = onClose
  }

  var body: some View {
    ZStack {
      if !isInSheet { EveningBackground() }
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          header
          ForEach(ShopItem.Shelf.allCases, id: \.self) { shelf in
            let items = store.catalog.items(on: shelf)
            if !items.isEmpty { section(shelf, items: items) }
          }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, isInSheet ? Spacing.large : Spacing.small)
        // Room for the strip at the foot, so the last cards can scroll out from under it.
        .padding(.bottom, Spacing.page + Spacing.large)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .overlay(alignment: .bottom) {
      if let notice {
        strip(notice)
          .padding(.horizontal, Spacing.medium)
          .padding(.bottom, Spacing.small)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .sensoryFeedback(.success, trigger: purchases)
    .sensoryFeedback(.warning, trigger: notice) { _, new in
      if case .short = new { true } else { false }
    }
  }

  // MARK: - Header

  @ViewBuilder private var header: some View {
    if isInSheet {
      SheetHeader("Shop", onClose: onClose) { controls }
    } else {
      HStack(spacing: Spacing.small) {
        Text("Shop")
          .billetType(.title)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: Spacing.small)
        controls
      }
    }
  }

  @ViewBuilder private var controls: some View {
    StampPlate(balance: store.stamps)
      .accessibilityIdentifier("shopStamps")
    IconButton("archivebox.fill", label: "Closet", action: onOpenCloset)
      .overlay(alignment: .topTrailing) { closetBadge }
      .symbolEffect(.bounce, value: purchases)
      .accessibilityIdentifier("shopCloset")
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

  // MARK: - Shelves

  private func section(_ shelf: ShopItem.Shelf, items: [ShopItem]) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      VStack(alignment: .leading, spacing: 0) {
        Text(shelf.title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        Text(shelf.subtitle)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
      }
      LazyVGrid(columns: columns, spacing: Spacing.small) {
        ForEach(items) { item in
          card(item)
        }
      }
    }
  }

  private var columns: [GridItem] {
    typeSize.isAccessibilitySize
      ? [GridItem(.flexible())]
      : [GridItem(.flexible(), spacing: Spacing.small), GridItem(.flexible())]
  }

  private func card(_ item: ShopItem) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      ShopThumbnail(item: item, thumbnail: thumbnail)
        .overlay(alignment: .topTrailing) { badge(item) }
        .scaleEffect(popped == item.id ? 1.06 : 1)
        .accessibilityHidden(true)
      Text(item.name)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(2, reservesSpace: true)
        .fixedSize(horizontal: false, vertical: true)
      buttons(item)
    }
    .padding(Spacing.small)
    .card()
    .modifier(CardPreviewShape())
    .contextMenu {
      menu(item)
    } preview: {
      ShopItemCloser(item: item, thumbnail: thumbnail)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shopItem-\(item.id)")
  }

  @ViewBuilder private func badge(_ item: ShopItem) -> some View {
    let owned = store.owned(item)
    if case .style(let choice) = item.look, style.shows(choice) {
      Image(systemName: "checkmark.circle.fill")
        .font(IconStyle.font)
        .foregroundStyle(Palette.gold.color)
        .padding(Spacing.small)
    } else if !item.ownsAtMostOne, owned > 0 {
      Text(verbatim: "×\(owned)")
        .billetType(.label)
        .foregroundStyle(Palette.gold.color)
        .padding(Spacing.small)
    }
  }

  @ViewBuilder private func buttons(_ item: ShopItem) -> some View {
    HStack(spacing: Spacing.hair) {
      if item.isPlaceable, store.owned(item) > 0 {
        Button {
          onPlace(item)
        } label: {
          PillLabel("Place", systemImage: "hand.point.up.left.fill", rank: .secondary)
        }
        .billetButton(.secondary)
        .accessibilityLabel("Place \(item.name) in your room")
        .accessibilityIdentifier("shopPlace-\(item.id)")
      }
      priceButton(item)
    }
  }

  @ViewBuilder private func priceButton(_ item: ShopItem) -> some View {
    if checkout.isOwned(item) {
      if case .style(let choice) = item.look, !style.shows(choice) {
        Button {
          use(choice)
        } label: {
          PillLabel("Use", systemImage: "checkmark", rank: .secondary)
        }
        .billetButton(.secondary)
        .accessibilityLabel("Use \(item.name)")
        .accessibilityIdentifier("shopUse-\(item.id)")
      } else {
        PillLabel("Owned", systemImage: "checkmark", rank: .secondary)
          .opacity(0.7)
          .accessibilityLabel("\(item.name), owned")
      }
    } else {
      let short = checkout.shortfall(for: item)
      Button {
        buy(item)
      } label: {
        if short > 0 {
          PillLabel("\(short) more", systemImage: "seal", rank: .secondary)
        } else {
          PillLabel("\(item.price)", systemImage: "seal.fill", rank: .primary)
        }
      }
      .billetButton(short > 0 ? .secondary : .primary)
      .accessibilityLabel(
        short > 0
          ? "\(item.name), \(item.price) stamps. You need \(short) more."
          : "Buy \(item.name) for \(item.price) stamps"
      )
      .accessibilityIdentifier("shopBuy-\(item.id)")
    }
  }

  @ViewBuilder private func menu(_ item: ShopItem) -> some View {
    if case .style(let choice) = item.look, let onTryOn, !style.shows(choice) {
      Button("Try it on in your room", systemImage: "eye") { onTryOn(choice) }
    }
    if item.isPlaceable, store.owned(item) > 0 {
      Button("Place in your room", systemImage: "hand.point.up.left") { onPlace(item) }
    }
    if !checkout.isOwned(item) {
      Button("Buy for \(item.price) stamps", systemImage: "seal") { buy(item) }
    }
  }

  // MARK: - The strip at the foot

  @ViewBuilder private func strip(_ notice: Notice) -> some View {
    HStack(spacing: Spacing.small) {
      switch notice {
      case .bought(let receipt):
        Image(systemName: receipt.needsPlacing ? "archivebox.fill" : "checkmark.circle.fill")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
          .symbolEffect(.bounce, value: receipt.id)
        Text(Self.boughtLine(receipt))
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
          .lineLimit(2)
        Spacer(minLength: Spacing.small)
        if receipt.needsPlacing {
          Button("Place") { onPlace(receipt.item) }
            .billetType(.label)
            .foregroundStyle(Palette.light.color)
            .frame(minHeight: Target.minimum)
        }
        Button("Undo") { undo(receipt) }
          .billetType(.label)
          .foregroundStyle(Palette.light.color)
          .frame(minHeight: Target.minimum)
          .accessibilityIdentifier("shopUndo")
      case .short(let item, let by):
        Image(systemName: "seal")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
        VStack(alignment: .leading, spacing: 2) {
          Text(by == 1 ? "1 more stamp for \(item.name)" : "\(by) more stamps for \(item.name)")
            .billetType(.label)
            .foregroundStyle(Palette.paper.color)
          Text(Self.earning)
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: Spacing.small)
        IconButton("xmark", label: "Close") { dismissNotice() }
      }
    }
    .padding(.leading, Spacing.medium)
    .padding(.trailing, Spacing.small)
    .padding(.vertical, Spacing.hair)
    .frame(minHeight: Target.row)
    .background(Palette.plate.color.opacity(0.94), in: .rect(cornerRadius: Radius.card))
    .overlay {
      RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        .strokeBorder(Palette.lightWarm.color.opacity(Glow.edgeOpacity), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shopNotice")
  }

  /// How stamps come, for someone short of them. Nothing in the app pays stamps out: each pair
  /// starts with a grant, and buying more is still to come.
  static let earning =
    "Stamps aren't earned by doing things here: every pair starts with a gift of them, and you'll be able to get more in the shop soon."

  static func boughtLine(_ receipt: ShopCheckout.Receipt) -> String {
    let name = receipt.item.name
    switch receipt.item.look {
    case .furniture:
      return receipt.needsPlacing ? "\(name) is in your closet" : "\(name) is in your room"
    case .style: return "\(name) is in your window"
    case .treat: return "\(name) is in your closet"
    case .material: return "\(name) is yours"
    }
  }

  // MARK: - Actions

  private func buy(_ item: ShopItem) {
    switch checkout.buy(item) {
    case .bought(let receipt):
      events(.shopItemBought(item.id, price: item.price))
      purchases += 1
      pop(item)
      show(.bought(receipt))
      Task {
        try? await Task.sleep(for: ShopCheckout.undoWindow)
        checkout.settle(receipt)
        if self.notice == .bought(receipt) { dismissNotice() }
      }
    case .short(let by):
      show(.short(item, by: by))
      Task {
        try? await Task.sleep(for: .seconds(8))
        if self.notice == .short(item, by: by) { dismissNotice() }
      }
    case .owned, .refused:
      break
    }
  }

  private func undo(_ receipt: ShopCheckout.Receipt) {
    checkout.undo(receipt)
    dismissNotice()
  }

  private func use(_ choice: RoomStyleItem) {
    checkout.use(choice)
  }

  private func pop(_ item: ShopItem) {
    guard !reduceMotion else { return }
    withAnimation(.spring(duration: 0.18, bounce: 0.5)) { popped = item.id }
    Task {
      try? await Task.sleep(for: .milliseconds(180))
      withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
        if popped == item.id { popped = nil }
      }
    }
  }

  private func show(_ next: Notice) {
    withAnimation(reduceMotion ? nil : Motion.spring) { notice = next }
  }

  private func dismissNotice() {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { notice = nil }
  }
}

/// The shape a long press lifts a card in: its own rounded corners.
private struct CardPreviewShape: ViewModifier {
  func body(content: Content) -> some View {
    #if os(iOS)
      content.contentShape(.contextMenuPreview, .rect(cornerRadius: Radius.card))
    #else
      content
    #endif
  }
}

/// A compact pill for a card's buttons: a symbol and a few words, at least 44 points tall.
private struct PillLabel: View {
  let title: String
  let systemImage: String
  let rank: ButtonRank

  @Environment(\.isEnabled) private var isEnabled

  init(_ title: String, systemImage: String, rank: ButtonRank) {
    self.title = title
    self.systemImage = systemImage
    self.rank = rank
  }

  var body: some View {
    HStack(spacing: Spacing.hair) {
      Image(systemName: systemImage)
        .imageScale(.small)
        .accessibilityHidden(true)
      Text(title)
        .billetType(.action)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .contentTransition(.numericText())
    }
    .foregroundStyle(rank == .primary ? Palette.ink.color : Palette.paper.color)
    .padding(.horizontal, Spacing.small + Spacing.hair)
    .frame(maxWidth: .infinity, minHeight: Target.minimum)
    .contentShape(.capsule)
  }
}

/// An item's picture on its plate: the scene's still of it once made, the flat glyph until then.
struct ShopThumbnail: View {
  let item: ShopItem
  let thumbnail: ShopView.Thumbnail

  @State private var image: CGImage?
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        if let image {
          Image(decorative: image, scale: displayScale)
            .resizable()
            .scaledToFit()
            .transition(.opacity)
        } else {
          ShopItemGlyph(item: item)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .task(id: ThumbnailKey(item: item.id, side: side.rounded())) {
        guard side > 0 else { return }
        let made = await thumbnail(item, side.rounded(), displayScale)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = made }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .background(
      RadialGradient(
        colors: [Palette.lightWarm.color.opacity(0.16), Palette.plate.color.opacity(0.5)],
        center: .init(x: 0.5, y: 0.42), startRadius: 4, endRadius: 120),
      in: .rect(cornerRadius: Radius.plate)
    )
    .clipShape(.rect(cornerRadius: Radius.plate))
  }

  private struct ThumbnailKey: Hashable {
    let item: ShopItem.ID
    let side: CGFloat
  }
}

/// The closer look a long press brings up: the picture large, with what the item is.
private struct ShopItemCloser: View {
  let item: ShopItem
  let thumbnail: ShopView.Thumbnail

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      ShopThumbnail(item: item, thumbnail: thumbnail)
        .frame(width: 280, height: 280)
      Text(item.name)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      Text("\(item.detail) · \(item.price) stamps")
        .billetType(.label)
        .foregroundStyle(Palette.muted.color)
    }
    .padding(Spacing.medium)
    .background(Palette.raised.color)
    .preferredColorScheme(.dark)
  }
}

/// The flat picture of an item, while its still is being made or where the scene has none.
struct ShopItemGlyph: View {
  private let item: ShopItem
  @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

  init(item: ShopItem) {
    self.item = item
  }

  var body: some View {
    Image(systemName: item.symbol)
      .font(.system(size: size))
      .foregroundStyle(item.tint.color)
  }
}

/// The wallet balance, as a plate with a stamp.
struct StampPlate: View {
  private let balance: Int

  init(balance: Int) {
    self.balance = balance
  }

  var body: some View {
    HStack(spacing: Spacing.hair) {
      Image(systemName: "seal.fill")
        .font(IconStyle.font)
      Text(verbatim: "\(balance)")
        .billetType(.numeral)
        .lineLimit(1)
        .fixedSize()
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
