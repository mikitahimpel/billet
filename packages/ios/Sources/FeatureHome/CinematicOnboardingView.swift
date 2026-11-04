import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The words over the first-launch scene.
struct OnboardingHeading: Hashable {
  var title: String
  var detail: String

  static let welcome = OnboardingHeading(
    title: "A little house for two",
    detail: "Draw a note and the cat carries it to your partner's wall.")
}

/// The first launch as a scene: the camera glides in over a windowsill of candles to a soft
/// beating heart, the title settles in, and then `actions` come up at the bottom. A tap anywhere
/// cuts the flight short. Once it has landed the scene shows `rest`, which the steps after the
/// welcome change. With no scene that has one, it is the evening background.
struct CinematicOnboardingView<Actions: View>: View {
  private let scenes: [any PetScene]
  private let lighting: RoomLighting
  /// `nil` for a replay, which always flies in and remembers nothing.
  private let memory: OnboardingMemory?
  private let heading: OnboardingHeading
  private let rest: OnboardingSceneState
  private let onEvent: (OnboardingSceneEvent) -> Void
  /// Goes back a step, from the top-left corner; `nil` where there is no step to go back to.
  private let back: (() -> Void)?
  private let actions: () -> Actions

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var intro: OnboardingIntro
  @State private var heartTaps = 0
  @State private var joins = 0

  /// `startsAtRest` opens without the flight even when `memory` has not seen it.
  init(
    scenes: [any PetScene], lighting: RoomLighting, memory: OnboardingMemory?,
    startsAtRest: Bool = false,
    heading: OnboardingHeading = .welcome,
    rest: OnboardingSceneState = OnboardingSceneState(moment: .resting),
    onEvent: @escaping (OnboardingSceneEvent) -> Void = { _ in },
    back: (() -> Void)? = nil,
    @ViewBuilder actions: @escaping () -> Actions
  ) {
    self.scenes = scenes
    self.lighting = lighting
    self.memory = memory
    self.heading = heading
    self.rest = rest
    self.onEvent = onEvent
    self.back = back
    self.actions = actions
    _intro = State(
      initialValue: OnboardingIntro(seenBefore: startsAtRest || memory?.introSeen == true))
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
    .sensoryFeedback(.success, trigger: joins)
    .task {
      if scene == nil { send(.arrived) }
      guard !intro.showsTitle else { return }
      try? await Task.sleep(for: OnboardingIntro.titleDelay)
      send(.titleDue)
    }
  }

  private var sceneState: OnboardingSceneState {
    intro.step == .ready ? rest : intro.scene
  }

  private var sceneView: AnyView? {
    let state = sceneState
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
        .padding(.top, HeadingWords.top)
        // Clear of the back button, the same each side so the words stay centred.
        .padding(.horizontal, back == nil ? 0 : Target.minimum + Spacing.hair)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Spacing.medium)
    .overlay(alignment: .topLeading) {
      if let back {
        BackButton(action: back)
          .padding(.leading, Spacing.medium)
          .padding(.top, HeadingWords.top - (Target.minimum - BilletType.title.lineHeight) / 2)
          .opacity(intro.showsActions ? 1 : 0)
          .allowsHitTesting(intro.showsActions)
          .accessibilityHidden(!intro.showsActions)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: back == nil)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: Spacing.small) { actions() }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity)
        .opacity(intro.showsActions ? 1 : 0)
        .offset(y: intro.showsActions || reduceMotion ? 0 : 24)
        .allowsHitTesting(intro.showsActions)
        .accessibilityHidden(!intro.showsActions)
        .animation(reduceMotion ? .easeOut(duration: 0.4) : .easeOut(duration: 0.7), value: intro)
    }
    // Past this the title and the buttons no longer fit on a small phone together.
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
  }

  private var title: some View {
    let shown = intro.showsTitle
    return HeadingWords(heading: heading, showsDetail: intro.showsActions)
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
    case .joined: joins += 1
    case .codeTapped: break
    }
    onEvent(event)
  }

  private func send(_ event: OnboardingIntro.Event) {
    intro.send(event)
    if intro.step == .ready { memory?.rememberIntro() }
  }
}

/// A title and its explanation over a scene, on a calm dark scrim that comes down from the top of
/// the screen, so the words stay crisp over the bright window and lights. A new heading fades in
/// over the old one as a whole: moving one block from the old words to the new would slide the
/// lines across the screen while they rewrap, which reads as crooked text.
struct HeadingWords: View {
  let heading: OnboardingHeading
  var showsDetail = true

  /// The widest the words get.
  static let measure: CGFloat = 300
  /// From the top of the safe area to the title: close under the status bar, so the words sit
  /// above the scene's window rather than over it.
  static let top = Spacing.medium

  var body: some View {
    ZStack(alignment: .top) {
      VStack(spacing: Spacing.small) {
        BalancedLines {
          Text(heading.title)
            .billetType(.title)
            .foregroundStyle(Palette.paper.color)
            .accessibilityAddTraits(.isHeader)
            .lineLimit(3)
            .minimumScaleFactor(0.75)
        }
        // When the keyboard leaves little room, the title keeps its lines and the explanation
        // gives way.
        .layoutPriority(1)
        BalancedLines {
          Text(heading.detail)
            .billetType(.body)
            .foregroundStyle(Palette.paper.color.opacity(0.9))
            .minimumScaleFactor(0.7)
        }
        .opacity(showsDetail ? 1 : 0)
      }
      // A tight dark edge, not a glow: it only firms up the letters' outline.
      .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
      .multilineTextAlignment(.center)
      // One block, as narrow as a short paragraph, so its lines stay short and even.
      .frame(maxWidth: Self.measure)
      .frame(maxWidth: .infinity)
      .id(heading)
      .transition(.opacity)
    }
    .animation(.easeInOut(duration: 0.45), value: heading)
    .background(alignment: .top) { HeadingScrim() }
  }
}

/// The dark behind the words: from the top of the screen down to the last line of the words it
/// is a steady dark, then it fades out over the scene below them. Paper-white words over it keep
/// AA contrast even where pure white, a light's glow, is behind.
struct HeadingScrim: View {
  /// How far below the words the scrim fades out.
  static let fade: CGFloat = 110
  /// How much of the scene's light it holds back under the words.
  static let dark = 0.66

  /// The brightest the scene can look through the scrim: pure white, darkened.
  static var brightestBehindWords: Swatch {
    let level = UInt32(((1 - dark) * 255).rounded(.up))
    return Swatch(level * 0x010101)
  }

  var body: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [.black.opacity(0.8), .black.opacity(Self.dark)], startPoint: .top,
        endPoint: .bottom)
      LinearGradient(
        colors: [.black.opacity(Self.dark), .black.opacity(0)], startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: Self.fade)
      .padding(.bottom, -Self.fade)
    }
    // Out to the screen's edges and up under the status bar.
    .padding(.horizontal, -60)
    .padding(.top, -200)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
