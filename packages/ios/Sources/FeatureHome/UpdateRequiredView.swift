import DesignSystem
import SwiftUI

/// Shown, and nothing else, when this build is older than the service accepts.
struct UpdateRequiredView: View {
  let link: UpdateLink

  @Environment(\.openURL) private var openURL

  var body: some View {
    ZStack {
      EveningBackground()
      VStack(spacing: Spacing.medium) {
        Image(systemName: "envelope.badge")
          .font(.system(size: 48, weight: .medium))
          .foregroundStyle(Palette.light.color)
          .lampGlow()
          .accessibilityHidden(true)
        Text("Time for a new billet")
          .billetType(.title)
          .foregroundStyle(Palette.paper.color)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
        Text("This version can no longer send or receive notes. Update to carry on.")
          .billetType(.body)
          .foregroundStyle(Palette.muted.color)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        BilletButton("Update billet", rank: .primary, systemImage: "arrow.down.circle") {
          if let url = link.url { openURL(url) }
        }
        .padding(.top, Spacing.small)
        .accessibilityIdentifier("updateBillet")
      }
      .padding(.horizontal, Spacing.wide)
      .frame(maxWidth: 420)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("updateRequired")
  }
}
