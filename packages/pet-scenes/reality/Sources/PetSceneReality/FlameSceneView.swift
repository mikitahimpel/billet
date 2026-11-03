import Pet
import PetScene
import RealityKit
import SwiftUI

/// Shows the streak's flame: the night, the room's window view through the opening, the 3D sill
/// with the flame, then the flame's bloom and a soft vignette.
///
/// The RealityView mounts once the scene is on screen and its stage pauses whenever it leaves it,
/// as the tab scenes do. A finger on the flame makes it lean that way.
struct FlameSceneView: View {
  let state: FlameSceneState
  let stages: TabStages
  let onEvent: @MainActor (FlameSceneEvent) -> Void

  @Environment(\.petSceneOnScreen) private var hostShowsScene
  @Environment(\.petSceneWindowView) private var windowView
  @Environment(\.petSceneViewArt) private var viewArt
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var plates = ViewPlateCache()
  @State private var isMounted = false
  @State private var isAppeared = false
  @State private var isDrawing = false
  @State private var isTouching = false

  private var isOnScreen: Bool {
    isAppeared && hostShowsScene && scenePhase == .active
  }

  var body: some View {
    let stage = stages.flameStage
    ZStack {
      FlameNight()
      if stage.screen.isLit && isDrawing { outside(stage).transition(.opacity) }
      if isMounted { reality(stage) }
      FlameBloom(screen: stage.screen).opacity(isDrawing ? 1 : 0)
      GlowVignette(look: .candle)
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: isDrawing)
    .ignoresSafeArea()
    .onAppear {
      stage.onEvent = { onEvent($0) }
      stage.begin(state)
      isAppeared = true
    }
    .onDisappear {
      isAppeared = false
      stage.touch(at: nil)
    }
    .onChange(of: state) { _, state in
      stage.onEvent = { onEvent($0) }
      stage.show(state)
    }
    .onChange(of: isOnScreen, initial: true) { _, onScreen in
      if onScreen { isMounted = true }
      stage.setOnScreen(onScreen)
    }
    .onChange(of: reduceMotion, initial: true) { _, reduced in stage.setReduceMotion(reduced) }
    .accessibilityElement()
    .accessibilityLabel(Self.label(state))
    .accessibilityAddTraits(.isImage)
  }

  /// What VoiceOver reads for the scene.
  static func label(_ state: FlameSceneState) -> String {
    let flame = state.flame
    let what =
      flame.isEmber
      ? "A warm ember glowing in a clay dish on a windowsill at night."
      : "\(flame.stage.title) on a windowsill at night, two tongues of flame twisting together."
    return [what, flame.caption, state.today.line].compactMap { $0 }.joined(separator: " ")
  }

  private static let firstFrame = Duration.milliseconds(450)

  private func reality(_ stage: FlameSceneStage) -> some View {
    RealityView { content in
      content.camera = .virtual
      content.add(stage.root)
      stage.start()
    }
    .task {
      try? await Task.sleep(for: Self.firstFrame)
      isDrawing = true
    }
    .onGeometryChange(for: CGSize.self) {
      $0.size
    } action: {
      stage.fit(to: $0)
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in
          let near = stage.touch(at: value.location)
          if near, !isTouching { onEvent(.touched) }
          isTouching = true
        }
        .onEnded { _ in
          stage.touch(at: nil)
          isTouching = false
        }
    )
  }

  /// The room's window view through the opening, always at night.
  private func outside(_ stage: FlameSceneStage) -> some View {
    TimelineView(.animation(minimumInterval: 0.05, paused: !isOnScreen || reduceMotion)) {
      context in
      let screen = stage.screen
      let state = WindowViewState(
        view: windowView.view, weather: windowView.shownWeather, hour: .night, time: 30,
        now: context.date.timeIntervalSinceReferenceDate, window: screen.window,
        home: screen.homeWindow.isEmpty ? screen.window : screen.homeWindow, lampOn: true)
      Group {
        if let art = viewArt?.view(state.view, state: state) {
          art
        } else {
          NativeWindowView(state: state, plates: plates)
        }
      }
      .clipShape(Opening(points: state.window))
      .opacity(state.window.isEmpty ? 0 : 1)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

/// The deep blue night the sill sits in, warmer low down where the flame is.
private struct FlameNight: View {
  var body: some View {
    LinearGradient(
      colors: [
        Color(cgColor: GenzColour(0x0E1424).cgColor), Color(cgColor: GenzColour(0x1E1420).cgColor),
        Color(cgColor: GenzColour(0x2A1A1C).cgColor),
      ], startPoint: .top, endPoint: .bottom
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

/// The flame's bloom in one Canvas, added onto the scene in screen blend.
private struct FlameBloom: View {
  let screen: FlameScreen

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let glows = screen.glows
    Canvas { canvas, _ in
      for glow in glows where glow.strength > 0.005 && glow.radius > 0 {
        let colour = Color(cgColor: glow.colour.cgColor)
        let strength = min(glow.strength, 1)
        let rect = CGRect(
          x: glow.centre.x - glow.radius, y: glow.centre.y - glow.radius,
          width: glow.radius * 2, height: glow.radius * 2)
        canvas.fill(
          Path(ellipseIn: rect),
          with: .radialGradient(
            Gradient(stops: [
              .init(color: colour.opacity(strength), location: 0),
              .init(color: colour.opacity(strength * 0.35), location: 0.35),
              .init(color: colour.opacity(0), location: 1),
            ]), center: glow.centre, startRadius: 0, endRadius: glow.radius))
      }
    }
    .blendMode(.screen)
    .opacity(screen.isLit ? 1 : 0)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: screen.isLit)
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
