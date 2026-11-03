import Foundation
import PetScene

/// The first-launch flight, as the screen over the scene follows it: the camera glides in, the
/// title settles in partway, and the buttons come once the camera is at its place. A tap cuts it
/// short. After the first time it opens already at rest.
struct OnboardingIntro: Equatable {
  enum Step: Equatable {
    /// The camera is gliding in; nothing over the scene yet.
    case flying
    /// The title has settled in; the camera is still on its way.
    case titled
    /// At rest, with the buttons.
    case ready
  }

  enum Event: Equatable {
    /// The moment in the flight the title is due.
    case titleDue
    /// The scene's camera reached its place.
    case arrived
    /// A tap cut the flight short.
    case skipped
  }

  /// Seconds into the flight the title settles in.
  static let titleDelay = Duration.milliseconds(3_400)

  private(set) var step: Step

  init(seenBefore: Bool) {
    step = seenBefore ? .ready : .flying
  }

  mutating func send(_ event: Event) {
    switch (step, event) {
    case (.flying, .titleDue): step = .titled
    case (.flying, .arrived), (.titled, .arrived), (.flying, .skipped), (.titled, .skipped):
      step = .ready
    case (.titled, .titleDue), (.ready, .titleDue), (.ready, .arrived), (.ready, .skipped):
      break
    }
  }

  var showsTitle: Bool { step != .flying }
  var showsActions: Bool { step == .ready }
  var canSkip: Bool { step != .ready }

  /// What the scene shows: flying in until the flight ends or is cut short.
  var scene: OnboardingSceneState {
    OnboardingSceneState(moment: step == .ready ? .resting : .arriving)
  }
}

/// Whether this phone has seen the first-launch flight, so it plays once.
struct OnboardingMemory {
  static let key = "onboarding.introSeen"

  let defaults: UserDefaults

  var introSeen: Bool { defaults.bool(forKey: Self.key) }

  func rememberIntro() {
    defaults.set(true, forKey: Self.key)
  }
}
