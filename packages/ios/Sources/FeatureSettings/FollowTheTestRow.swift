import DesignSystem
import SwiftUI

/// The first row of a Labs picker the server can also set: no choice on this phone, so the setting
/// is whatever the pair's test gives, else the standard one. Checked while nothing is chosen.
struct FollowTheTestRow: View {
  let subtitle: String
  let selected: Bool
  let identifier: String
  let follow: @MainActor () -> Void

  var body: some View {
    Button {
      withAnimation(Motion.spring) { follow() }
    } label: {
      ListRow("Follow the test", subtitle: subtitle) {
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
    .accessibilityIdentifier(identifier)
    .sensoryFeedback(.selection, trigger: selected)
  }
}
