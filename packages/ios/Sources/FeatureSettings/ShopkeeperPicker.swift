import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// Who keeps the 3D shop, one row each with a check on the chosen one. Saved with the Labs flags.
struct ShopkeeperPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Shopkeeper")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(Shopkeeper.allCases, id: \.self) { keeper in
          if keeper != Shopkeeper.allCases.first { ListDivider() }
          row(keeper)
        }
      }
    }
  }

  private func row(_ keeper: Shopkeeper) -> some View {
    let selected = model.shopkeeper == keeper
    return Button {
      withAnimation(Motion.spring) { model.setShopkeeper(keeper) }
    } label: {
      ListRow(keeper.title, subtitle: keeper.detail) {
        EmptyView()
      } trailing: {
        if selected {
          RowIcon("checkmark", color: Palette.gold)
            .transition(.opacity)
        }
      }
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("shopkeeper-\(keeper.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
