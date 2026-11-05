import PetScene
import SwiftUI

/// Whether this launch of the app still owes its way into the room. It lives as long as the
/// process, so a cold launch plays it and coming back from the background never does. A launch
/// that opened on the heart's scene has had its cinematic and skips this one.
@MainActor
final class LaunchCinematic {
  static let thisLaunch = LaunchCinematic()

  private var isClaimed = false

  /// True the first time it is asked this launch, unless the first-launch scene played; false
  /// every time after.
  func claim(onboardingPlayed: Bool) -> Bool {
    defer { isClaimed = true }
    return !isClaimed && !onboardingPlayed
  }
}

/// The launch's glide into the room, over the room's own view: from the first frame a warm dark
/// covers the room while it loads; once the room is built and starts its opening the cover fades,
/// the camera glides in, the lights come up and the cat looks up. A tap skips to the end. With
/// Reduce Motion nothing flies: the cover cross-fades to the room at its place.
struct LaunchGlide: ViewModifier {
  /// True while it plays. Starts true for a launch that owes it; the room sets it false at the end.
  @Binding var isPlaying: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var flyIn: PetSceneFlyIn?
  @State private var isCovered = true

  /// How long the room has to be built and on screen before the cover lifts anyway.
  static let roomAllowance = Duration.seconds(8)

  func body(content: Content) -> some View {
    content
      .environment(\.petSceneFlyIn, flyIn)
      .environment(\.petSceneOpeningStarted) { isCovered = false }
      .environment(\.petSceneOpeningEnded) { isPlaying = false }
      .overlay {
        if isPlaying {
          ZStack {
            LaunchCover()
              .opacity(isCovered ? 1 : 0)
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { skip() }
              .accessibilityElement()
              .accessibilityLabel("Skip the opening")
              .accessibilityAddTraits(.isButton)
              .accessibilityAction { skip() }
          }
          .ignoresSafeArea()
          .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: reduceMotion ? 0.5 : 0.9), value: isCovered)
      .animation(.easeOut(duration: 0.3), value: isPlaying)
      .task { await play() }
  }

  private func play() async {
    guard isPlaying else { return }
    flyIn = PetSceneFlyIn(id: 1, isSkipped: reduceMotion)
    // The room says when its opening starts and ends. These only free the screen if it never does.
    try? await Task.sleep(for: Self.roomAllowance)
    guard !Task.isCancelled else { return }
    isCovered = false
    try? await Task.sleep(for: .seconds(FlyInTimeline.length))
    guard !Task.isCancelled else { return }
    isPlaying = false
  }

  /// Jumps the glide to its end. A room still loading stays covered until it is built, and then
  /// shows at its place.
  private func skip() {
    flyIn?.isSkipped = true
  }
}

/// The dark the launch opens on: warm, as if the room's lights were about to come up.
private struct LaunchCover: View {
  var body: some View {
    RadialGradient(
      colors: [
        Color(red: 0.16, green: 0.09, blue: 0.06), Color(red: 0.05, green: 0.03, blue: 0.025),
      ], center: .center, startRadius: 0, endRadius: 520
    )
    .accessibilityHidden(true)
  }
}
