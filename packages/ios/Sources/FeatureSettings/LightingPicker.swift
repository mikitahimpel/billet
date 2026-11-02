import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// How the rooms are lit, one row per look with a check on the chosen one. Saved with the Labs
/// flags.
struct LightingPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Lighting")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(RoomLighting.allCases, id: \.self) { lighting in
          if lighting != RoomLighting.allCases.first { ListDivider() }
          row(lighting)
        }
      }
    }
  }

  private func row(_ lighting: RoomLighting) -> some View {
    let selected = model.lighting == lighting
    return Button {
      withAnimation(Motion.spring) { model.setLighting(lighting) }
    } label: {
      ListRow(lighting.title, subtitle: lighting.detail) {
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
    .accessibilityIdentifier("lighting-\(lighting.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
