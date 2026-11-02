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
        followRow
        ForEach(RoomStyle.allCases, id: \.self) { style in
          ListDivider()
          row(style)
        }
      }
    }
  }

  /// No Labs choice: the room is whatever the pair's test gives, or the standard room.
  private var followRow: some View {
    let selected = model.roomStyleOverride == nil
    return Button {
      withAnimation(Motion.spring) { model.followTheTest() }
    } label: {
      ListRow("Follow the test", subtitle: "What this pair's test gives, else the standard room.") {
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
    .accessibilityIdentifier("roomStyle-follow")
    .sensoryFeedback(.selection, trigger: selected)
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
