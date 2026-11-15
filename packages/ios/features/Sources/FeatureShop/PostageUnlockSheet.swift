#if canImport(UIKit)
  import Design
  import ShopInterface
  import SwiftUI

  /// Asks before a locked stamp or seal is bought from the composer: the piece, its price and the pair's coins. Short
  /// of coins the button says how many are missing and opens Coins.
  public struct PostageUnlockSheet: View {
    let postage: NotePostage
    let shop: ShopModel
    let buy: () -> Void

    public init(postage: NotePostage, shop: ShopModel, buy: @escaping () -> Void) {
      self.postage = postage
      self.shop = shop
      self.buy = buy
    }

    private var affordable: Bool { shop.coins >= postage.price }

    public var body: some View {
      BilletSheet(postage.name, size: .fit) {
        VStack(spacing: Space.l) {
          PostageArtView(postage, size: 80)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.l)
            .wellSurface(.card)
            .corners(.card)
            .accessibilityHidden(true)

          Text(
            "Yours for good, on every note either of you sends. Notes you get show theirs either way."
          )
          .font(.ourioCallout)
          .foregroundStyle(Ink.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: Space.s) {
            Text("Your coins")
              .font(.ourioCallout)
              .foregroundStyle(Ink.textSecondary)
            Spacer(minLength: Space.s)
            CoinPrice(price: shop.coins)
              .font(.ourioHeadline)
              .foregroundStyle(Ink.text)
          }
          .accessibilityElement(children: .combine)

          Button(action: buy) { label.frame(maxWidth: .infinity) }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("postageBuy")
            .accessibilityHint(affordable ? "Unlocks it for both of you" : "Opens Coins")
        }
      }
    }

    private var label: some View {
      HStack(spacing: Space.s) {
        if affordable {
          Text("Unlock for")
          CoinPrice(price: postage.price)
        } else {
          Image(systemName: "plus.circle.fill")
          Text("Need \(shop.shortBy(postage.price)) more")
            .monospacedDigit()
        }
      }
      .font(.ourioHeadline)
      .buyLabelFit()
    }
  }
#endif
