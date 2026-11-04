import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// Which room Home shows the cat in, one row per room with a check on the chosen one. Saved
/// with the Labs flags.
struct HomeRoomPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Room")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(HomeRoom.allCases, id: \.self) { room in
          if room != HomeRoom.allCases.first { ListDivider() }
          row(room)
        }
      }
    }
  }

  private func row(_ room: HomeRoom) -> some View {
    let selected = model.homeRoom == room
    return Button {
      withAnimation(Motion.spring) { model.setHomeRoom(room) }
    } label: {
      ListRow(room.title, subtitle: room.detail) {
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
    .accessibilityIdentifier("homeRoom-\(room.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
