import DesignSystem
import Pet
import SwiftUI

/// Where stamps come from, opened from the balance or from "N more". Says it plainly: stamps are
/// given, not earned, and not sold yet. With Labs on, a row of stamp packs sits below.
struct ShopStampsSheet: View {
  let balance: Int
  let gift: DailyGift
  let isGiftClaimed: Bool
  let giftEnds: Date
  let catalog: ShopCatalog
  let packs: any StampPackSource
  let showsPacks: Bool
  let onClaimGift: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.large) {
        SheetHeader("Stamps")
        HStack(spacing: Spacing.small) {
          Image(systemName: "seal.fill")
            .font(.system(size: 34))
          Text(verbatim: "\(balance)")
            .billetType(.display)
            .contentTransition(.numericText(value: Double(balance)))
        }
        .foregroundStyle(Palette.gold.color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You have \(balance) stamps")
        VStack(alignment: .leading, spacing: Spacing.small) {
          Text("Where stamps come from")
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
          ForEach(Self.ways, id: \.title) { way in
            HStack(alignment: .top, spacing: Spacing.small) {
              Image(systemName: way.symbol)
                .font(IconStyle.font)
                .foregroundStyle(Palette.gold.color)
                .frame(width: 28)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 2) {
                Text(way.title)
                  .billetType(.body)
                  .foregroundStyle(Palette.paper.color)
                Text(way.detail)
                  .billetType(.label)
                  .foregroundStyle(Palette.muted.color)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
        DailyGiftCard(
          gift: gift, catalog: catalog, isClaimed: isGiftClaimed, ends: giftEnds,
          onClaim: onClaimGift)
        if showsPacks { StampPacksRow(source: packs) }
      }
      .padding(Spacing.medium)
    }
    .scrollBounceBehavior(.basedOnSize)
  }

  private struct Way {
    let symbol: String
    let title: String
    let detail: String
  }

  private static let ways = [
    Way(
      symbol: "heart.fill", title: "A gift to start",
      detail: "Every pair begins with a pile of stamps, shared by the two of you."),
    Way(
      symbol: "gift.fill", title: "A gift every day",
      detail: "The shop has a free gift each day: some stamps or a treat for the cat."),
    Way(
      symbol: "bag.fill", title: "Packs, later",
      detail: "Buying packs of stamps will come, but not yet."),
  ]
}

/// Packs of stamps for money, behind Labs. The shop only draws what its source says: with none
/// for sale the row is a placeholder whose button does nothing.
struct StampPacksRow: View {
  let source: any StampPackSource

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack {
        Text("Stamp packs")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
        Spacer()
        OfferTag("Labs", systemImage: "flask.fill")
      }
      if source.packs.isEmpty {
        HStack(spacing: Spacing.small) {
          Image(systemName: "seal.fill")
            .font(IconStyle.font)
            .foregroundStyle(Palette.muted.color)
            .accessibilityHidden(true)
          Text("Not for sale yet")
            .billetType(.body)
            .foregroundStyle(Palette.muted.color)
          Spacer()
          PillLabel("Soon", systemImage: "clock", rank: .secondary)
            .fixedSize()
            .opacity(0.5)
        }
        .padding(Spacing.small)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shopStampPacksPlaceholder")
      } else {
        ForEach(source.packs) { pack in
          HStack(spacing: Spacing.small) {
            Image(systemName: "seal.fill")
              .font(IconStyle.font)
              .foregroundStyle(Palette.gold.color)
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(pack.displayName)
                .billetType(.body)
                .foregroundStyle(Palette.paper.color)
              Text("\(pack.stamps) stamps")
                .billetType(.caption)
                .foregroundStyle(Palette.muted.color)
            }
            Spacer()
            Button {
              source.buy(pack)
            } label: {
              PillLabel(pack.displayPrice, systemImage: "bag.fill", rank: .primary)
                .fixedSize()
            }
            .billetButton(.primary)
            .disabled(source.state == .buying || source.state == .pending)
          }
          .padding(Spacing.small)
          .card()
        }
      }
    }
  }
}

/// Buying something for the partner: the item, a few words to go with it, and the price.
struct ShopGiftSheet: View {
  let item: ShopItem
  let price: Int
  let shortfall: Int
  let thumbnail: ShopView.Thumbnail
  let onGive: (String?) -> Void

  @State private var note = ""
  @FocusState private var isWriting: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.medium) {
      SheetHeader("A gift for your partner")
      HStack(spacing: Spacing.medium) {
        ShopThumbnail(item: item, thumbnail: thumbnail)
          .frame(width: 96, height: 96)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name)
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
          Text("Arrives wrapped on their doormat")
            .billetType(.label)
            .foregroundStyle(Palette.muted.color)
        }
      }
      TextField("Add a note (optional)", text: $note, axis: .vertical)
        .lineLimit(2...3)
        .billetType(.body)
        .foregroundStyle(Palette.paper.color)
        .focused($isWriting)
        .padding(Spacing.small)
        .background(Palette.plate.color, in: .rect(cornerRadius: Radius.plate))
        .onChange(of: note) { _, new in
          if new.count > ShopCheckout.noteLimit {
            note = String(new.prefix(ShopCheckout.noteLimit))
          }
        }
        .accessibilityIdentifier("shopGiftNote")
      Text("\(note.count)/\(ShopCheckout.noteLimit)")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
      Button {
        onGive(note)
        dismiss()
      } label: {
        ButtonLabel(
          shortfall > 0 ? "\(shortfall) more stamps needed" : "Give for \(price) stamps",
          rank: .primary, systemImage: "gift.fill")
      }
      .billetButton(.primary)
      .disabled(shortfall > 0)
      .accessibilityIdentifier("shopGiftGive")
      Spacer(minLength: 0)
    }
    .padding(Spacing.medium)
    .onAppear { isWriting = true }
  }
}
