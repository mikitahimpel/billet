import DesignSystem
import SwiftUI
import WidgetBridge

/// The ground behind every screen: one row per ground, each with a swatch of its sky, and a
/// check on the chosen one. Saved with the Labs flags; the app changes at once.
struct EveningGroundPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Background")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(EveningGround.allCases, id: \.self) { ground in
          if ground != EveningGround.allCases.first { ListDivider() }
          row(ground)
        }
      }
    }
  }

  private func row(_ ground: EveningGround) -> some View {
    let selected = model.eveningGround == ground
    return Button {
      withAnimation(Motion.spring) { model.setEveningGround(ground) }
    } label: {
      ListRow(ground.title, subtitle: ground.detail) {
        RoundedRectangle(cornerRadius: Radius.paper / 2, style: .continuous)
          .fill(
            LinearGradient(
              colors: [ground.top.color, ground.middle.color, ground.foot.color],
              startPoint: .top, endPoint: .bottom)
          )
          .overlay(alignment: ground == .ember ? .bottom : .top) {
            Circle()
              .fill(ground.glow.color.opacity(0.5))
              .frame(width: 10, height: 10)
              .blur(radius: 4)
          }
          .frame(width: 28, height: 40)
          .overlay {
            RoundedRectangle(cornerRadius: Radius.paper / 2, style: .continuous)
              .strokeBorder(Palette.paper.color.opacity(0.15), lineWidth: 1)
          }
          .accessibilityHidden(true)
      } trailing: {
        if selected {
          RowIcon("checkmark", color: Palette.gold)
            .transition(.opacity)
        }
      }
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("ground-\(ground.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }
}
