import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// How Home is laid out: following the pair's test, or one row per variant with a check on the
/// chosen one. Saved with the Labs flags.
struct HomeVariantPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Home")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        FollowTheTestRow(
          subtitle: "What this pair's test gives, else the standard Home.",
          selected: model.homeVariantOverride == nil, identifier: "homeVariant-follow",
          follow: model.followTheHomeVariantTest)
        ForEach(HomeVariant.allCases, id: \.self) { variant in
          ListDivider()
          row(variant)
        }
      }
      if model.homeVariant == .nightAndDay { pretendHour }
    }
  }

  /// The hours to try the light of, beside the real clock.
  static let pretendHours = [7, 13, 19, 23]

  /// Lets the light of another hour be tried without waiting for it.
  private var pretendHour: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("Pretend hour")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
      SettingsGroup {
        hourRow(nil)
        ForEach(Self.pretendHours, id: \.self) { hour in
          ListDivider()
          hourRow(hour)
        }
      }
    }
  }

  private func hourRow(_ hour: Int?) -> some View {
    let selected = model.pretendHour == hour
    let title = hour.map { String(format: "%02d:00", $0) } ?? "The clock"
    return Button {
      model.setPretendHour(hour)
    } label: {
      ListRow(title) {
        EmptyView()
      } trailing: {
        if selected { RowIcon("checkmark", color: Palette.gold) }
      }
    }
    .buttonStyle(RowButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("pretendHour-\(hour.map(String.init) ?? "clock")")
  }

  private func row(_ variant: HomeVariant) -> some View {
    let selected = model.homeVariantOverride == variant
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
