#if canImport(UIKit)
  import Design
  import ShopInterface
  import SwiftUI

  /// The Shop's stamps and seals for notes, in the ink shelf's cards: the art, its name and the price pill, or
  /// "Owned" once the pair unlocked it. A buy plays the purchase moment like an ink.
  struct PostageShelf: View {
    let state: any ShopHost

    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
      Array(
        repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top),
        count: typeSize.isAccessibilitySize ? 2 : 3)
    }

    var body: some View {
      VStack(alignment: .leading, spacing: Space.m) {
        shelf("Stamps", NotePostage.stamps)
        shelf("Seals", NotePostage.seals)
      }
    }

    private func shelf(_ title: String, _ postage: [NotePostage]) -> some View {
      VStack(alignment: .leading, spacing: Space.m) {
        SectionHeader(title)
          .padding(.horizontal, Space.l)
        LazyVGrid(columns: columns, spacing: Space.m) {
          ForEach(postage) { card($0).id($0.id) }
        }
        .padding(.horizontal, Space.l)
      }
    }

    private func card(_ postage: NotePostage) -> some View {
      let owned = postage.isOwned(state.shop.owned)
      return VStack(spacing: Space.s) {
        PostageArtView(postage, size: 56)
          .frame(height: Size.button)
          .accessibilityHidden(true)
        // Two cards a row at the accessibility sizes leave no room for a bigger name than this.
        Text(postage.shortName)
          .font(.ourioHeadline)
          .foregroundStyle(Ink.text)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        Group {
          if owned {
            Chip("Owned", symbol: "checkmark")
          } else {
            Design.PriceButton(
              postage.price, label: "Unlock \(postage.name), \(postage.price) coins"
            ) { state.shop.buy(postage) }
          }
        }
        .frame(minHeight: Size.control)
      }
      .padding(CardMetrics.padding)
      .frame(maxWidth: .infinity)
      .cardSurface()
      .accessibilityElement(children: .contain)
      .accessibilityLabel(postage.name)
      .accessibilityIdentifier("shopPostage-\(postage.id)")
    }
  }
#endif
