import DesignSystem
import SwiftUI

/// The service's soft notice: one line under the top of the screen, styled like the connection
/// pill, which the user can close.
struct NoticeBanner: View {
  let text: String
  let onDismiss: () -> Void

  var body: some View {
    HStack(spacing: Spacing.small) {
      Circle()
        .fill(Palette.gold.color)
        .frame(width: Spacing.small, height: Spacing.small)
        .accessibilityHidden(true)
      Text(text)
        .billetType(.label)
        .foregroundStyle(Palette.paper.color)
        .lineLimit(3)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(.footnote, weight: .semibold))
          .foregroundStyle(Palette.muted.color)
          .frame(width: Target.minimum, height: Target.minimum)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding(.leading, Spacing.medium)
    .frame(minHeight: Target.minimum)
    .floatingGlass()
    // Below the row the connection pill takes at the top of Home.
    .padding(.top, Spacing.small * 2 + Target.minimum)
    .padding(.horizontal, Spacing.medium)
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("serviceNotice")
  }
}
