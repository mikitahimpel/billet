import DesignSystem
import Pet
import SwiftUI
import WidgetBridge

/// What the styled rooms' window looks out on: one row per view with a check on the chosen one,
/// then its weather and hour. "As made" leaves the weather to the view and the hour to the room.
/// Saved with the Labs flags; the window changes without a restart.
struct WindowViewPicker: View {
  let model: WidgetFeaturesModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text("View")
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
      SettingsGroup {
        ForEach(WindowView.allCases, id: \.self) { view in
          if view != WindowView.allCases.first { ListDivider() }
          row(view)
        }
        ListDivider()
        chips(
          "Weather", options: ViewWeather.allCases, chosen: model.windowView.weather,
          title: \.title, id: "weather"
        ) { weather in
          var choice = model.windowView
          choice.weather = weather
          model.setWindowView(choice)
        }
        ListDivider()
        chips(
          "Hour", options: ViewHour.allCases, chosen: model.windowView.hour, title: \.title,
          id: "hour"
        ) { hour in
          var choice = model.windowView
          choice.hour = hour
          model.setWindowView(choice)
        }
      }
    }
  }

  private func row(_ view: WindowView) -> some View {
    let selected = model.windowView.view == view
    return Button {
      withAnimation(Motion.spring) {
        var choice = model.windowView
        choice.view = view
        model.setWindowView(choice)
      }
    } label: {
      ListRow(view.title, subtitle: view.detail) {
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
    .accessibilityIdentifier("view-\(view.rawValue)")
    .sensoryFeedback(.selection, trigger: selected)
  }

  /// A row of chips for one modifier: "As made" first, then each option.
  private func chips<Option: Hashable & RawRepresentable<String>>(
    _ label: String, options: [Option], chosen: Option?, title: KeyPath<Option, String>,
    id: String, choose: @escaping (Option?) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      Text(label)
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.small) {
          chip("As made", selected: chosen == nil, id: "\(id)-asMade") { choose(nil) }
          ForEach(options, id: \.self) { option in
            chip(option[keyPath: title], selected: chosen == option, id: "\(id)-\(option.rawValue)")
            {
              choose(option)
            }
          }
        }
      }
    }
    .padding(.horizontal, Spacing.medium)
    .padding(.vertical, Spacing.small)
  }

  private func chip(_ text: String, selected: Bool, id: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Text(text)
        .billetType(.caption)
        .foregroundStyle(selected ? Palette.ink.color : Palette.muted.color)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(
          Capsule().fill(selected ? Palette.gold.color : Palette.raisedTop.color))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier(id)
    .sensoryFeedback(.selection, trigger: selected)
  }
}
