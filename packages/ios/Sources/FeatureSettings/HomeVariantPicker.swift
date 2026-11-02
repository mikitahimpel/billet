import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// How Home is laid out, one row per variant with a check on the chosen one. Saved with the Labs
/// flags.
struct HomeVariantPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Home")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(HomeVariant.allCases, id: \.self) { variant in
          if variant != HomeVariant.allCases.first { ListDivider() }
          row(variant)
        }
      }
    }
  }

  private func row(_ variant: HomeVariant) -> some View {
    let selected = model.homeVariant == variant
    return Button {
      withAnimation(Motion.spring) { model.setHomeVariant(variant) }
    } label: {
      ListRow(variant.title, subtitle: variant.detail) {
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
    .accessibilityIdentifier("homeVariant-\(variant.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
