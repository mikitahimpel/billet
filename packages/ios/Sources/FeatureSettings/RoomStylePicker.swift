import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// The room style, one row per style with a check on the chosen one. Saved with the Labs flags.
struct RoomStylePicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Room style")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        FollowTheTestRow(
          subtitle: "What this pair's test gives, else the standard room.",
          selected: model.roomStyleOverride == nil, identifier: "roomStyle-follow",
          follow: model.followTheTest)
        ForEach(RoomStyle.allCases, id: \.self) { style in
          ListDivider()
          row(style)
        }
      }
    }
  }

  private func row(_ style: RoomStyle) -> some View {
    let selected = model.roomStyleOverride == style
    return Button {
      withAnimation(Motion.spring) { model.setRoomStyle(style) }
    } label: {
      ListRow(style.title, subtitle: style.detail) {
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
    .accessibilityIdentifier("roomStyle-\(style.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
