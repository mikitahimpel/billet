#if canImport(UIKit)
  import Design
  import SwiftUI
  import WidgetUI

  struct BundleCard: View {
    let state: any ShopHost
    let bundle: ShopBundle
    var open: (ShopItem) -> Void
    var openSet: () -> Void = {}

    private var items: [ShopItem] {
      bundle.itemIDs.compactMap { Catalog.item($0, cat: state.petName) }
    }
    private var quote: (price: Int, sum: Int)? {
      state.shop.offers.price(of: bundle, owned: state.shop.owned)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: Space.m) {
        pieces
        CardActions {
          Button(action: openSet) {
            title.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
          }
          .buttonStyle(PressScaleStyle())
        } trail: {
          SetBuyButton(state: state, set: bundle)
        }
      }
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface()
      .perfFlattened()
    }

    private var title: some View {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Space.s) {
          Text(bundle.name)
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
          if let quote, quote.sum > quote.price {
            Chip(
              "−\(Int(((1 - Double(quote.price) / Double(quote.sum)) * 100).rounded()))%",
              style: .honey)
          }
        }
        Text(bundle.blurb)
          .font(.ourioCaption)
          .foregroundStyle(Ink.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }

    private var pieces: some View {
      HStack(spacing: Space.xs) {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          if index > 0 {
            Image(systemName: "plus")
              .font(.ourioCaption.weight(.bold))
              .foregroundStyle(Ink.textTertiary)
              .accessibilityHidden(true)
          }
          Button {
            open(item)
          } label: {
            RarityFrame(rarity: item.rarity) {
              if let image = Thumbnails.image(item.thumbnail, maxPixels: 256) {
                Image(uiImage: image).resizable().scaledToFit()
                  .padding(Space.s)
              }
            }
            .frame(width: 72, height: 72)
            .overlay(alignment: .bottomTrailing) {
              if state.shop.owned.contains(item.id) { OwnedCheck().offset(x: 4, y: 4) }
            }
          }
          .buttonStyle(PressScaleStyle())
          .accessibilityLabel(item.name + (state.shop.owned.contains(item.id) ? ", owned" : ""))
        }
      }
    }
  }
#endif
