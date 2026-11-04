import DesignSystem
import Pet
import SwiftUI

/// The week's bundle across the top of the shop: its pieces fanned out on a warm plate, what it is,
/// how much less it costs than its parts, and when the next one comes.
struct FeaturedBanner<Price: View>: View {
  let bundle: ShopBundle
  let items: [ShopItem]
  let sum: Int
  let ends: Date
  let thumbnail: ShopView.Thumbnail
  @ViewBuilder let price: () -> Price

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      BundleArt(items: items, thumbnail: thumbnail, side: 112)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(warmPlate, in: .rect(cornerRadius: Radius.plate))
        .overlay(alignment: .topLeading) {
          OfferTag("This week", systemImage: "sparkles")
            .padding(Spacing.small)
        }
        .overlay(alignment: .topTrailing) {
          ValueTag(percent: bundle.discount)
            .padding(Spacing.small)
        }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.hair) {
        Text(bundle.name)
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Text(bundle.blurb)
          .billetType(.label)
          .foregroundStyle(Palette.muted.color)
          .fixedSize(horizontal: false, vertical: true)
        RotationTimer(prefix: "New set in", ends: ends)
      }
      HStack(spacing: Spacing.small) {
        StruckPrice(sum)
        price()
      }
    }
    .padding(Spacing.small)
    .card()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shopFeatured")
  }

  private var warmPlate: some ShapeStyle {
    RadialGradient(
      colors: [Palette.lightWarm.color.opacity(0.32), Palette.clayNight.color.opacity(0.55)],
      center: .init(x: 0.5, y: 0.35), startRadius: 8, endRadius: 220)
  }
}

/// A bundle's pieces side by side, slightly overlapping and turned, as if set down on a table.
struct BundleArt: View {
  let items: [ShopItem]
  let thumbnail: ShopView.Thumbnail
  let side: CGFloat

  var body: some View {
    let shown = Array(items.prefix(4))
    HStack(spacing: -side * 0.28) {
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
        ShopThumbnail(item: item, thumbnail: thumbnail, plated: false)
          .frame(width: side, height: side)
          .rotationEffect(.degrees(Self.tilt(index, of: shown.count)))
          .offset(y: index.isMultiple(of: 2) ? 4 : -4)
          .zIndex(Double(shown.count - abs(index * 2 - shown.count + 1)))
      }
    }
  }

  private static func tilt(_ index: Int, of count: Int) -> Double {
    guard count > 1 else { return 0 }
    return (Double(index) / Double(count - 1) - 0.5) * 14
  }
}

/// One of the day's deals: a small card in a row that scrolls sideways.
struct DealCard<Price: View>: View {
  let deal: ShopDeal
  let thumbnail: ShopView.Thumbnail
  @ViewBuilder let price: () -> Price

  @ScaledMetric(relativeTo: .body) private var width: CGFloat = 156

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      ShopThumbnail(item: deal.item, thumbnail: thumbnail)
        .overlay(alignment: .topLeading) {
          ValueTag(percent: deal.discount).padding(Spacing.hair)
        }
        .accessibilityHidden(true)
      Text(deal.item.name)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(2, reservesSpace: true)
      StruckPrice(deal.item.price)
      price()
    }
    .padding(Spacing.small)
    .frame(width: width)
    .card()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shopDeal-\(deal.item.id)")
  }
}

/// A bundle in the list: its pieces, its name, the sum it would cost, and its price.
struct BundleCard<Price: View>: View {
  let bundle: ShopBundle
  let items: [ShopItem]
  let sum: Int
  let thumbnail: ShopView.Thumbnail
  @ViewBuilder let price: () -> Price

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(alignment: .top, spacing: Spacing.small) {
        VStack(alignment: .leading, spacing: Spacing.hair) {
          if bundle.isStarter {
            OfferTag("Just once", systemImage: "star.fill")
          }
          Text(bundle.name)
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
          Text(bundle.blurb)
            .billetType(.label)
            .foregroundStyle(Palette.muted.color)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        ValueTag(percent: bundle.discount)
      }
      BundleArt(items: items, thumbnail: thumbnail, side: 76)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .accessibilityHidden(true)
      HStack(spacing: Spacing.small) {
        if !items.isEmpty { StruckPrice(sum) }
        price()
      }
    }
    .padding(Spacing.small)
    .card()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("shopBundle-\(bundle.id)")
  }
}

/// The free gift of the day: closed with a wobble until opened, then a count down to the next.
struct DailyGiftCard: View {
  let gift: DailyGift
  let catalog: ShopCatalog
  let isClaimed: Bool
  let ends: Date
  let onClaim: () -> Void

  @State private var bursts = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: Spacing.small) {
      Image(systemName: isClaimed ? "gift" : "gift.fill")
        .font(.system(size: 30))
        .foregroundStyle(Palette.gold.color)
        .symbolEffect(
          .wiggle.byLayer, options: .repeat(.periodic(delay: 2.5)),
          isActive: !isClaimed && !reduceMotion
        )
        .frame(width: 52, height: 52)
        .background(Palette.plate.color, in: .circle)
        .overlay { StampBurst(count: bursts) }
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(isClaimed ? "Today's gift is opened" : "A gift for today")
          .billetType(.body)
          .foregroundStyle(Palette.paper.color)
        if isClaimed {
          RotationTimer(prefix: "Next one in", ends: ends)
        } else {
          Text("Free, once a day")
            .billetType(.caption)
            .foregroundStyle(Palette.muted.color)
        }
      }
      Spacer(minLength: Spacing.small)
      if !isClaimed {
        Button {
          bursts += 1
          onClaim()
        } label: {
          PillLabel("Open", systemImage: "sparkles", rank: .primary)
            .fixedSize()
        }
        .billetButton(.primary)
        .accessibilityLabel("Open today's gift: \(Self.describe(gift.reward, catalog: catalog))")
        .accessibilityIdentifier("shopDailyGift")
      } else {
        Text(Self.describe(gift.reward, catalog: catalog))
          .billetType(.label)
          .foregroundStyle(Palette.gold.color)
          .multilineTextAlignment(.trailing)
      }
    }
    .padding(Spacing.small)
    .card()
    .sensoryFeedback(.success, trigger: bursts)
    .accessibilityElement(children: .contain)
  }

  static func describe(_ reward: DailyGift.Reward, catalog: ShopCatalog) -> String {
    switch reward {
    case .stamps(let stamps): "\(stamps) stamps"
    case .item(let id): catalog.item(id)?.name ?? "A treat"
    }
  }
}

/// Stamps flying out of the gift as it opens. Each burst is drawn once and fades.
struct StampBurst: View {
  let count: Int

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if count > 0, !reduceMotion {
        ForEach(0..<10, id: \.self) { index in
          FlyingStamp(index: index)
        }
        .id(count)
      }
    }
    .allowsHitTesting(false)
  }

  private struct FlyingStamp: View {
    let index: Int
    @State private var flown = false

    var body: some View {
      let angle = Double(index) / 10 * 2 * .pi + 0.3
      let reach = 46 + Double(index % 3) * 14
      Image(systemName: "seal.fill")
        .font(.system(size: 12 + CGFloat(index % 3) * 3))
        .foregroundStyle(index.isMultiple(of: 3) ? Palette.lightWarm.color : Palette.gold.color)
        .offset(
          x: flown ? cos(angle) * reach : 0,
          y: flown ? sin(angle) * reach - 20 : 0
        )
        .scaleEffect(flown ? 1 : 0.3)
        .opacity(flown ? 0 : 1)
        .rotationEffect(.degrees(flown ? Double(index * 40) : 0))
        .onAppear {
          withAnimation(.easeOut(duration: 0.9).delay(Double(index) * 0.015)) { flown = true }
        }
    }
  }
}

/// A count down to a real change of the shop, ticking by itself.
struct RotationTimer: View {
  let prefix: String
  let ends: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      HStack(spacing: Spacing.hair) {
        Image(systemName: "clock")
          .imageScale(.small)
          .accessibilityHidden(true)
        Text("\(prefix) \(Self.left(from: context.date, to: ends))")
          .monospacedDigit()
      }
      .billetType(.caption)
      .foregroundStyle(Palette.muted.color)
    }
  }

  /// "3 days", "5 h 12 min" or "12:04", the way a game shows what is left.
  static func left(from now: Date, to end: Date) -> String {
    let seconds = max(Int(end.timeIntervalSince(now)), 0)
    let days = seconds / 86_400
    let hours = seconds % 86_400 / 3_600
    let minutes = seconds % 3_600 / 60
    if days >= 1 { return days == 1 ? "1 day \(hours) h" : "\(days) days" }
    if hours >= 1 { return "\(hours) h \(minutes) min" }
    return String(format: "%d:%02d", minutes, seconds % 60)
  }
}

/// What it would cost one by one, struck through.
struct StruckPrice: View {
  private let price: Int

  init(_ price: Int) {
    self.price = price
  }

  var body: some View {
    HStack(spacing: 2) {
      Image(systemName: "seal")
        .imageScale(.small)
      Text(verbatim: "\(price)")
    }
    .billetType(.label)
    .foregroundStyle(Palette.muted.color)
    .strikethrough(true, color: Palette.muted.color)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Usually \(price) stamps")
  }
}

/// How much less than usual, as a gold tag.
struct ValueTag: View {
  let percent: Int

  var body: some View {
    Text("−\(percent)%")
      .billetType(.label)
      .foregroundStyle(Palette.ink.color)
      .padding(.horizontal, Spacing.small)
      .padding(.vertical, 2)
      .background(Palette.gold.color, in: .capsule)
      .accessibilityLabel("\(percent) percent less than its parts")
  }
}

/// A small word on an offer, such as "This week".
struct OfferTag: View {
  private let title: String
  private let systemImage: String

  init(_ title: String, systemImage: String) {
    self.title = title
    self.systemImage = systemImage
  }

  var body: some View {
    Label(title, systemImage: systemImage)
      .labelStyle(.titleAndIcon)
      .billetType(.caption)
      .foregroundStyle(Palette.paper.color)
      .padding(.horizontal, Spacing.small)
      .padding(.vertical, 2)
      .background(Palette.plate.color.opacity(0.85), in: .capsule)
  }
}

/// What the cat does with a thing, in a small bubble under it.
struct CatReactionLine: View {
  let reaction: String

  var body: some View {
    HStack(alignment: .top, spacing: Spacing.hair) {
      Image(systemName: "cat.fill")
        .imageScale(.small)
        .foregroundStyle(Palette.gold.color)
        .accessibilityHidden(true)
      Text(reaction)
        .billetType(.caption)
        .foregroundStyle(Palette.paper.color.opacity(0.85))
        .lineLimit(2, reservesSpace: true)
    }
    .accessibilityElement(children: .combine)
  }
}
