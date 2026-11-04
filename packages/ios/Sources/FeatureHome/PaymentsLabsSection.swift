import DesignSystem
import Pet
import SwiftUI

/// Labs → Payments: opens the stamp packs, then whatever the build's store adds (the mock store's
/// switches).
struct PaymentsLabsSection: View {
  let stampShop: StampShop
  let shop: ShopStore
  let extra: AnyView?

  @State private var showsPacks = false

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Payments")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        Button {
          showsPacks = true
        } label: {
          HStack {
            Text("Stamp packs")
              .billetType(.body)
              .foregroundStyle(Palette.paper.color)
            Spacer()
            StampPlate(balance: shop.stamps)
          }
          .padding(Spacing.medium)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("labs.payments.packs")
      }
      if let extra {
        SettingsGroup {
          extra
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .sheet(isPresented: $showsPacks) {
      StampPacksSheet(stampShop: stampShop, shop: shop)
        .billetSheet([.medium, .large])
    }
  }
}
