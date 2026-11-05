import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// Which furniture fills the styled rooms, one row per set with a check on the chosen one. Saved
/// with the Labs flags.
struct FurniturePicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Furniture")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(RoomFurniture.allCases, id: \.self) { furniture in
          if furniture != RoomFurniture.allCases.first { ListDivider() }
          row(furniture)
        }
      }
    }
  }

  private func row(_ furniture: RoomFurniture) -> some View {
    let selected = model.furniture == furniture
    return Button {
      withAnimation(Motion.spring) { model.setFurniture(furniture) }
    } label: {
      ListRow(furniture.title, subtitle: furniture.detail) {
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
    .accessibilityIdentifier("furniture-\(furniture.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
