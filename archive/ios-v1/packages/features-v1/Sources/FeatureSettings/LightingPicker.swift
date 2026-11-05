import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// How the rooms are lit: following the pair's test, or one row per look with a check on the
/// chosen one. Saved with the Labs flags.
struct LightingPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Lighting")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        FollowTheTestRow(
          subtitle: "What this pair's test gives, else the standard lighting.",
          selected: model.lightingOverride == nil, identifier: "lighting-follow",
          follow: model.followTheLightingTest)
        ForEach(RoomLighting.allCases, id: \.self) { lighting in
          ListDivider()
          row(lighting)
        }
      }
    }
  }

  private func row(_ lighting: RoomLighting) -> some View {
    let selected = model.lightingOverride == lighting
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
