import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The first launch as a scene: the camera glides in over a windowsill of candles to a soft
/// beating heart, the title settles in, and then `actions` come up at the bottom. A tap anywhere
/// cuts the flight short. With no scene that has one, it is the evening background.
struct CinematicOnboardingView<Actions: View>: View {
  private let scenes: [any PetScene]
  private let lighting: RoomLighting
  /// `nil` for a replay, which always flies in and remembers nothing.
  private let memory: OnboardingMemory?
  private let actions: () -> Actions

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var intro: OnboardingIntro
  @State private var heartTaps = 0

  init(
    scenes: [any PetScene], lighting: RoomLighting, memory: OnboardingMemory?,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.scenes = scenes
    self.lighting = lighting
    self.memory = memory
    self.actions = actions
    _intro = State(initialValue: OnboardingIntro(seenBefore: memory?.introSeen ?? false))
  }

  var body: some View {
    let scene = sceneView
    ZStack {
      if let scene {
        scene
          .environment(\.petSceneLighting, lighting)
          .ignoresSafeArea()
      } else {
        EveningBackground()
      }
      overlay
      if intro.canSkip {
        Color.clear
          .contentShape(Rectangle())
          .ignoresSafeArea()
          .onTapGesture { send(.skipped) }
          .accessibilityElement()
          .accessibilityLabel("Skip the opening")
          .accessibilityAddTraits(.isButton)
          .accessibilityAction { send(.skipped) }
      }
    }
    .preferredColorScheme(.dark)
    .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: heartTaps)
    .task {
      if scene == nil { send(.arrived) }
      guard !intro.showsTitle else { return }
      try? await Task.sleep(for: OnboardingIntro.titleDelay)
      send(.titleDue)
    }
  }

  private var sceneView: AnyView? {
    let state = intro.scene
    for scene in scenes {
      if let view = scene.makeOnboardingScene(state: state, onEvent: { handle($0) }) {
        return view
      }
    }
    return nil
  }

  private var overlay: some View {
    VStack(spacing: Spacing.large) {
      title
        .padding(.top, Spacing.wide)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.medium)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: Spacing.small) { actions() }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .opacity(intro.showsActions ? 1 : 0)
        .offset(y: intro.showsActions || reduceMotion ? 0 : 24)
        .allowsHitTesting(intro.showsActions)
        .accessibilityHidden(!intro.showsActions)
        .animation(reduceMotion ? .easeOut(duration: 0.4) : .easeOut(duration: 0.7), value: intro)
    }
  }

  private var title: some View {
    let shown = intro.showsTitle
    return VStack(spacing: Spacing.small) {
      Text("A little house for two")
        .billetType(.title)
        .foregroundStyle(Palette.paper.color)
        .shadow(color: Color(red: 1, green: 0.55, blue: 0.4).opacity(0.55), radius: 18)
        .accessibilityAddTraits(.isHeader)
      Text("Draw a note and the cat carries it to your partner's wall.")
        .billetType(.body)
        .foregroundStyle(Palette.paper.color.opacity(0.78))
        .opacity(intro.showsActions ? 1 : 0)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .opacity(shown ? 1 : 0)
    .blur(radius: shown || reduceMotion ? 0 : 10)
    .scaleEffect(shown || reduceMotion ? 1 : 1.05)
    .offset(y: shown || reduceMotion ? 0 : -10)
    .animation(reduceMotion ? .easeOut(duration: 0.5) : .easeOut(duration: 1.4), value: intro)
    .accessibilityHidden(!shown)
  }

  private func handle(_ event: OnboardingSceneEvent) {
    switch event {
    case .arrived: send(.arrived)
    case .heartTapped: heartTaps += 1
    }
  }

  private func send(_ event: OnboardingIntro.Event) {
    intro.send(event)
    if intro.step == .ready { memory?.rememberIntro() }
  }
}
