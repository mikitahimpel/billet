import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The first launch played again from Labs, over everything, without touching the pair: the
/// flight from the dark every time, and nothing remembered.
struct OnboardingReplay: View {
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let onClose: () -> Void

  /// Bumped to play the flight again from the start.
  @State private var take = 0

  var body: some View {
    CinematicOnboardingView(scenes: scenes, lighting: lighting, memory: nil) {
      GlassGroup {
        VStack(spacing: Spacing.small) {
          BilletButton("Play again", rank: .primary, systemImage: "arrow.counterclockwise") {
            take += 1
          }
          BilletButton("Close", rank: .secondary, action: onClose)
        }
      }
    }
    .id(take)
  }
}
