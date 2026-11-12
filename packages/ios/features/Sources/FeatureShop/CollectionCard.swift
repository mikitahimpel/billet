#if canImport(UIKit)
  import Design
  import SwiftUI
  import WidgetUI

  /// The bonus can be collected once every piece is owned.
  struct CollectionCard: View {
    let state: any ShopHost
    let collection: ShopCollection
    var open: (ShopItem) -> Void

    @State private var claims = 0
    @State private var collecting = false

    private var items: [ShopItem] {
      collection.itemIDs.compactMap { Catalog.item($0, cat: state.petName) }
    }
    private static let columns = 4
    private var rows: [[ShopItem]] {
      stride(from: 0, to: items.count, by: Self.columns).map {
        Array(items[$0..<min($0 + Self.columns, items.count)])
      }
    }
    private var have: Int { collection.owned(of: state.shop.owned) }
    private var claimed: Bool { state.shop.bonuses.contains(collection.id) }

    var body: some View {
      VStack(alignment: .leading, spacing: Space.m) {
        HStack(alignment: .firstTextBaseline) {
          Text(collection.name)
            .font(.ourioHeadline)
            .foregroundStyle(Ink.text)
          Spacer(minLength: Space.s)
          Text("\(have)/\(collection.itemIDs.count)")
            .font(.ourioHeadline.monospacedDigit())
            .foregroundStyle(Ink.accentText)
            .contentTransition(.numericText())
        }
        ProgressBar(value: Double(have), total: Double(collection.itemIDs.count))
          .accessibilityLabel("\(have) of \(collection.itemIDs.count) collected")

        // Not lazy: a card is a handful of tiles, and rows built on scroll made the card's height and rows jump.
        VStack(spacing: Space.s) {
          ForEach(rows.indices, id: \.self) { row in
            HStack(spacing: Space.s) {
              ForEach(0..<Self.columns, id: \.self) { column in
                if column < rows[row].count {
                  slot(rows[row][column])
                } else {
                  Color.clear.frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                }
              }
            }
          }
        }

        Hairline()
        bonus
      }
      .padding(CardMetrics.padding)
      .cardSurface()
      .perfFlattened()
      .haptic(.success, trigger: claims)
      .animation(Motion.spring(), value: have)
    }

    private func slot(_ item: ShopItem) -> some View {
      let owns = state.shop.owned.contains(item.id)
      return Button {
        open(item)
      } label: {
        Group {
          if let image = Thumbnails.image(item.thumbnail, maxPixels: 256) {
            Image(uiImage: image).resizable().scaledToFit().padding(Space.xs)
          }
        }
        .grayscale(owns ? 0 : 1)
        .opacity(owns ? 1 : 0.4)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .wellSurface()
        .overlay(alignment: .bottomTrailing) {
          if owns { OwnedCheck().offset(x: 3, y: 3) }
        }
      }
      .buttonStyle(PressScaleStyle())
      .accessibilityLabel(item.name + (owns ? ", owned" : ", missing"))
    }

    @ViewBuilder private var bonus: some View {
      CardActions {
        HStack(spacing: Space.s) {
          Image(systemName: claimed ? "checkmark.seal.fill" : "sparkles")
            .foregroundStyle(Color.honey)
            .accessibilityHidden(true)
          Group {
            if claimed {
              Text("Bonus collected: \(collection.bonus) coins")
            } else {
              Text("Complete it for \(collection.bonus) coins")
            }
          }
          .font(.ourioCallout)
          .foregroundStyle(Ink.textSecondary)
        }
      } trail: {
        if state.shop.canClaimBonus(collection) {
          PrimaryButton("Collect", fullWidth: false) {
            collecting = true
            Task {
              if await state.shop.claimBonus(collection) { claims += 1 }
              collecting = false
            }
          }
          .disabled(collecting)
        }
      }
    }
  }
#endif
