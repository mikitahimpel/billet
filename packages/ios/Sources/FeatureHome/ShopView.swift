import CoreGraphics
import DesignSystem
import Pet
import SwiftUI

/// The shop, laid out like a good game store for two: the week's bundle at the top, a free gift
/// each day, three deals a day, the bundles, things for the cat with what it does with them, and
/// then every shelf. Every price is one tap, and for a few seconds the purchase can be taken back.
///
/// The offers follow from the pair's room code and the date, so both phones show the same, and
/// each timer runs to a real change. Nothing is scarce: nothing runs out, and nothing is hidden.
///
/// In a tab it has the evening behind it; in a sheet (``View/billetSheet(_:)``) the sheet's ground.
struct ShopView: View {
  /// Makes a still picture of an item, `side` points square at `scale` pixels a point.
  typealias Thumbnail =
    @MainActor (ShopItem, _ side: CGFloat, _ scale: CGFloat) async ->
    CGImage?

  /// What the shop needs from the pair beyond its store.
  struct Context {
    /// Seeds the offers. Both phones of the pair have the same: the room's code.
    var pair: String
    /// Where packs of stamps would be bought.
    var stampPacks: any StampPackSource
    /// Whether the stamps sheet shows the stamp packs row (Labs).
    var showsStampPacks: Bool
  }

  /// What the strip at the foot says.
  private enum Notice: Equatable {
    case bought(ShopCheckout.Receipt)
    case short(String, by: Int)
  }

  /// An item about to be bought for the partner, at `price`.
  private struct Giving: Identifiable {
    let item: ShopItem
    let price: Int
    var id: ShopItem.ID { item.id }
  }

  private let store: ShopStore
  private let checkout: ShopCheckout
  private let style: RoomStyle
  private let context: Context
  private let thumbnail: Thumbnail
  private let onPlace: (ShopItem) -> Void
  private let onTryOn: ((RoomStyleItem) -> Void)?
  private let onOpenCloset: () -> Void
  private let onClose: (() -> Void)?

  @State private var notice: Notice?
  @State private var purchases = 0
  @State private var popped: String?
  @State private var now = Date.now
  @State private var showsStamps = false
  @State private var giving: Giving?
  @State private var seen: Set<String> = []
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
    context: Context,
    thumbnail: @escaping Thumbnail,
    onPlace: @escaping (ShopItem) -> Void,
    onTryOn: ((RoomStyleItem) -> Void)?,
    onOpenCloset: @escaping () -> Void,
    onClose: (() -> Void)? = nil
  ) {
    self.store = store
    self.checkout = checkout
    self.style = style
    self.context = context
    self.thumbnail = thumbnail
    self.onPlace = onPlace
    self.onTryOn = onTryOn
    self.onOpenCloset = onOpenCloset
    self.onClose = onClose
  }

  private var offers: ShopOffers {
    ShopOffers(pair: context.pair, now: now, catalog: store.catalog)
  }

  var body: some View {
    let offers = offers
    ZStack {
      if !isInSheet { EveningBackground() }
      ScrollView {
        VStack(alignment: .leading, spacing: Spacing.large) {
          header
          if let featured = offers.featured { featuredBanner(featured, ends: offers.featuredEnds) }
          dailyGift(offers)
          deals(offers)
          bundles(offers.bundles)
          catShelf
          ForEach([ShopItem.Shelf.furniture, .decor, .views], id: \.self) { shelf in
            let items = store.catalog.items(on: shelf)
            if !items.isEmpty { section(shelf.title, subtitle: shelf.subtitle, items: items) }
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
    // Wakes when the deals or the week's bundle change, so the shop shows the new ones.
    .task(id: now) {
      let next = min(offers.dayEnds, offers.featuredEnds)
      try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 1)))
      guard !Task.isCancelled else { return }
      now = .now
    }
    .sheet(isPresented: $showsStamps) {
      ShopStampsSheet(
        balance: store.stamps, gift: offers.gift,
        isGiftClaimed: store.state.hasClaimed(offers.gift),
        giftEnds: offers.dayEnds, catalog: store.catalog, packs: context.stampPacks,
        showsPacks: context.showsStampPacks, onClaimGift: { claim(offers.gift) }
      )
      .billetSheet([.medium, .large])
    }
    .sheet(item: $giving) { giving in
      ShopGiftSheet(
        item: giving.item, price: giving.price,
        shortfall: checkout.shortfall(price: giving.price), thumbnail: thumbnail
      ) { note in
        give(giving.item, price: giving.price, note: note)
      }
      .billetSheet([.medium])
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
    Button {
      showsStamps = true
    } label: {
      StampPlate(balance: store.stamps)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Where stamps come from")
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

  // MARK: - Offers

  private func featuredBanner(_ bundle: ShopBundle, ends: Date) -> some View {
    let left = checkout.remaining(of: bundle)
    return FeaturedBanner(
      bundle: bundle, items: bundle.items(in: store.catalog), sum: left.sum, ends: ends,
      thumbnail: thumbnail
    ) {
      bundleButton(bundle, left: left)
    }
    .scaleEffect(popped == bundle.id ? 1.03 : 1)
    .onAppear { viewed(bundle.id) }
  }

  private func dailyGift(_ offers: ShopOffers) -> some View {
    DailyGiftCard(
      gift: offers.gift, catalog: store.catalog, isClaimed: store.state.hasClaimed(offers.gift),
      ends: offers.dayEnds, onClaim: { claim(offers.gift) })
  }

  private func deals(_ offers: ShopOffers) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      heading("Today's deals", subtitle: nil) {
        RotationTimer(prefix: "New in", ends: offers.dayEnds)
      }
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: Spacing.small) {
          ForEach(offers.deals) { deal in
            DealCard(deal: deal, thumbnail: thumbnail) {
              dealButton(deal)
            }
            .scaleEffect(popped == deal.id ? 1.06 : 1)
            .contextMenu {
              menu(deal.item, price: deal.price)
            } preview: {
              ShopItemCloser(item: deal.item, price: deal.price, thumbnail: thumbnail)
            }
            .onAppear { viewed("deal-\(deal.id)") }
          }
        }
        .padding(.vertical, Spacing.hair)
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
    }
  }

  @ViewBuilder private func bundles(_ bundles: [ShopBundle]) -> some View {
    let shown = bundles.filter { !($0.isStarter && store.state.hasBought(bundle: $0.id)) }
    if !shown.isEmpty {
      VStack(alignment: .leading, spacing: Spacing.small) {
        heading("Bundles", subtitle: "Sets that go together, for less") { EmptyView() }
        ForEach(shown) { bundle in
          let left = checkout.remaining(of: bundle)
          BundleCard(
            bundle: bundle, items: bundle.items(in: store.catalog), sum: left.sum,
            thumbnail: thumbnail
          ) {
            bundleButton(bundle, left: left)
          }
          .scaleEffect(popped == bundle.id ? 1.03 : 1)
          .onAppear { viewed(bundle.id) }
        }
      }
    }
  }

  @ViewBuilder private var catShelf: some View {
    let items = store.catalog.items(on: .cat)
    if !items.isEmpty {
      section(
        "For your cat", subtitle: "Treats, toys and beds, and what the cat does with them",
        items: items)
    }
  }

  // MARK: - Shelves

  private func heading<Trailing: View>(
    _ title: String, subtitle: String?, @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(alignment: .lastTextBaseline, spacing: Spacing.small) {
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .accessibilityAddTraits(.isHeader)
        if let subtitle {
          Text(subtitle)
            .billetType(.label)
            .foregroundStyle(Palette.muted.color)
        }
      }
      Spacer(minLength: Spacing.small)
      trailing()
    }
  }

  private func section(_ title: String, subtitle: String, items: [ShopItem]) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      heading(title, subtitle: subtitle) { EmptyView() }
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
      if let reaction = item.catReaction {
        CatReactionLine(reaction: reaction)
      }
      Spacer(minLength: 0)
      buttons(item)
    }
    .padding(Spacing.small)
    // Cards in a row are as tall as the tallest, their buttons on one line.
    .frame(maxHeight: .infinity, alignment: .top)
    .card()
    .modifier(CardPreviewShape())
    .contextMenu {
      menu(item, price: item.price)
    } preview: {
      ShopItemCloser(item: item, price: item.price, thumbnail: thumbnail)
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
      ownedButton(item)
    } else {
      PriceButton(
        name: item.name, price: item.price, shortfall: checkout.shortfall(for: item),
        identifier: "shopBuy-\(item.id)"
      ) {
        perform(checkout.buy(item), name: item.name, pop: item.id)
      }
    }
  }

  @ViewBuilder private func ownedButton(_ item: ShopItem) -> some View {
    if case .style(let choice) = item.look, !style.shows(choice) {
      Button {
        checkout.use(choice)
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
  }

  @ViewBuilder private func dealButton(_ deal: ShopDeal) -> some View {
    if checkout.isOwned(deal.item) {
      ownedButton(deal.item)
    } else {
      PriceButton(
        name: deal.item.name, price: deal.price, shortfall: checkout.shortfall(price: deal.price),
        identifier: "shopBuy-deal-\(deal.id)"
      ) {
        perform(checkout.buy(deal), name: deal.item.name, pop: deal.id)
      }
    }
  }

  @ViewBuilder private func bundleButton(
    _ bundle: ShopBundle, left: (items: [ShopItem], price: Int, sum: Int)
  ) -> some View {
    if left.items.isEmpty {
      PillLabel("All yours", systemImage: "checkmark", rank: .secondary)
        .opacity(0.7)
        .accessibilityLabel("\(bundle.name), all owned")
    } else {
      PriceButton(
        name: bundle.name, price: left.price, shortfall: checkout.shortfall(price: left.price),
        identifier: "shopBuy-\(bundle.id)"
      ) {
        perform(checkout.buy(bundle), name: bundle.name, pop: bundle.id)
      }
    }
  }

  @ViewBuilder private func menu(_ item: ShopItem, price: Int) -> some View {
    if case .style(let choice) = item.look, let onTryOn, !style.shows(choice) {
      Button("Try it on in your room", systemImage: "eye") { onTryOn(choice) }
    }
    if item.isPlaceable, store.owned(item) > 0 {
      Button("Place in your room", systemImage: "hand.point.up.left") { onPlace(item) }
    }
    if !checkout.isOwned(item) {
      Button("Buy for \(price) stamps", systemImage: "seal") {
        perform(checkout.buy(item), name: item.name, pop: item.id)
      }
    }
    if !item.ownsAtMostOne {
      Button("Give to your partner", systemImage: "gift") {
        giving = Giving(item: item, price: price)
      }
    }
  }

  // MARK: - The strip at the foot

  @ViewBuilder private func strip(_ notice: Notice) -> some View {
    HStack(spacing: Spacing.small) {
      switch notice {
      case .bought(let receipt):
        Image(systemName: Self.boughtSymbol(receipt))
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
      case .short(let name, let by):
        Image(systemName: "seal")
          .font(IconStyle.font)
          .foregroundStyle(Palette.gold.color)
        VStack(alignment: .leading, spacing: 2) {
          Text(by == 1 ? "1 more stamp for \(name)" : "\(by) more stamps for \(name)")
            .billetType(.label)
            .foregroundStyle(Palette.paper.color)
          Button("Where stamps come from") {
            dismissNotice()
            showsStamps = true
          }
          .billetType(.caption)
          .foregroundStyle(Palette.light.color)
          .accessibilityIdentifier("shopShortHow")
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

  static func boughtSymbol(_ receipt: ShopCheckout.Receipt) -> String {
    switch receipt.kind {
    case .gift: "gift.fill"
    case .forUs: receipt.needsPlacing ? "archivebox.fill" : "checkmark.circle.fill"
    }
  }

  static func boughtLine(_ receipt: ShopCheckout.Receipt) -> String {
    if case .gift = receipt.kind { return "\(receipt.item.name) is wrapped for your partner" }
    if let bundle = receipt.bundle {
      return receipt.needsPlacing
        ? "\(bundle.name) is yours. Some of it is in your closet"
        : "\(bundle.name) is in your room"
    }
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

  /// Shows what a tap on a price did, and counts it.
  private func perform(_ outcome: ShopCheckout.Outcome, name: String, pop key: String) {
    switch outcome {
    case .bought(let receipt):
      switch receipt.kind {
      case .gift: events(.shopGiftSent(receipt.item.id, price: receipt.price))
      case .forUs:
        if let bundle = receipt.bundle {
          events(.shopBundleBought(bundle.id, price: receipt.price))
        } else {
          events(.shopItemBought(receipt.item.id, price: receipt.price))
        }
      }
      purchases += 1
      pop(key)
      show(.bought(receipt))
      Task {
        try? await Task.sleep(for: ShopCheckout.undoWindow)
        checkout.settle(receipt)
        if self.notice == .bought(receipt) { dismissNotice() }
      }
    case .short(let by):
      show(.short(name, by: by))
      Task {
        try? await Task.sleep(for: .seconds(8))
        if self.notice == .short(name, by: by) { dismissNotice() }
      }
    case .owned, .refused:
      break
    }
  }

  private func give(_ item: ShopItem, price: Int, note: String?) {
    perform(checkout.give(item, price: price, note: note), name: item.name, pop: item.id)
  }

  private func undo(_ receipt: ShopCheckout.Receipt) {
    if checkout.undo(receipt) {
      events(.shopPurchaseUndone(receipt.bundle?.id ?? receipt.item.id, stamps: receipt.price))
    }
    dismissNotice()
  }

  private func claim(_ gift: DailyGift) {
    guard store.claim(gift) == .applied else { return }
    events(.shopDailyGiftClaimed(gift.reward))
  }

  /// Counts an offer the first time it comes on screen while the shop is open.
  private func viewed(_ offer: String) {
    guard seen.insert(offer).inserted else { return }
    events(.shopOfferViewed(offer))
  }

  private func pop(_ key: String) {
    guard !reduceMotion else { return }
    withAnimation(.spring(duration: 0.18, bounce: 0.5)) { popped = key }
    Task {
      try? await Task.sleep(for: .milliseconds(180))
      withAnimation(.spring(duration: 0.35, bounce: 0.4)) {
        if popped == key { popped = nil }
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

/// A price as a button: the stamps it costs, or how many more are needed. One tap buys.
private struct PriceButton: View {
  let name: String
  let price: Int
  let shortfall: Int
  let identifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      if shortfall > 0 {
        PillLabel("\(shortfall) more", systemImage: "seal", rank: .secondary)
      } else {
        PillLabel("\(price)", systemImage: "seal.fill", rank: .primary)
      }
    }
    .billetButton(shortfall > 0 ? .secondary : .primary)
    .accessibilityLabel(
      shortfall > 0
        ? "\(name), \(price) stamps. You need \(shortfall) more."
        : "Buy \(name) for \(price) stamps"
    )
    .accessibilityIdentifier(identifier)
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
struct PillLabel: View {
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
  /// On its own warm plate, or bare, to stand on another.
  var plated = true

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
        center: .init(x: 0.5, y: 0.42), startRadius: 4, endRadius: 120
      )
      .opacity(plated ? 1 : 0),
      in: .rect(cornerRadius: Radius.plate)
    )
    .clipShape(.rect(cornerRadius: plated ? Radius.plate : 0))
  }

  private struct ThumbnailKey: Hashable {
    let item: ShopItem.ID
    let side: CGFloat
  }
}

/// The closer look a long press brings up: the picture large, with what the item is. For a thing
/// made for the cat, the cat is there too, already taken with it.
struct ShopItemCloser: View {
  let item: ShopItem
  let price: Int
  let thumbnail: ShopView.Thumbnail

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      ShopThumbnail(item: item, thumbnail: thumbnail)
        .frame(width: 280, height: 280)
        .overlay(alignment: .bottomLeading) {
          if let reaction = item.catReaction { CatTakenWith(reaction: reaction) }
        }
      Text(item.name)
        .billetType(.heading)
        .foregroundStyle(Palette.paper.color)
      Text("\(item.detail) · \(price) stamps")
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

/// The cat beside a thing made for it, with hearts rising and its reaction in a bubble.
private struct CatTakenWith: View {
  let reaction: String

  @State private var beat = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(alignment: .bottom, spacing: Spacing.hair) {
      ZStack(alignment: .topTrailing) {
        Image(systemName: "cat.fill")
          .font(.system(size: 44))
          .foregroundStyle(Palette.paper.color)
          .symbolEffect(.bounce, value: beat)
        Image(systemName: "heart.fill")
          .font(.system(size: 16))
          .foregroundStyle(Palette.clayLit.color)
          .offset(x: 10, y: -12)
          .symbolEffect(.pulse, isActive: !reduceMotion)
      }
      Text(reaction)
        .billetType(.label)
        .foregroundStyle(Palette.ink.color)
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.hair)
        .background(Palette.paper.color, in: .rect(cornerRadius: Radius.plate))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Spacing.small)
    .task {
      guard !reduceMotion else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1.6))
        beat += 1
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Your cat: \(reaction)")
  }
}
