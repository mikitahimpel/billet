import Pet
import PetScene
import SwiftUI

/// Choosing the cat together: the cats on their cushions, a gold heart over this phone's pick
/// and a rose paw over the partner's, and round the cat both picked, a ring for each that fills
/// while each holds the cat.
struct AdoptionSceneView: View {
  let state: AdoptionSceneState
  let stages: TabStages
  let onEvent: @MainActor (AdoptionSceneEvent) -> Void

  var body: some View {
    let stage = stages.adoptionStage
    ZStack {
      TabSceneView(stage: stage)
      AdoptionMarksLayer(marks: stage.marks, state: state, onEvent: onEvent)
    }
    .onAppear {
      stage.onEvent = { onEvent($0) }
      stage.begin(state)
    }
    .onChange(of: state) { _, state in
      stage.onEvent = { onEvent($0) }
      stage.show(state)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .accessibilityActions {
      if state.moment == .choosing {
        ForEach(Array(state.cats.indices), id: \.self) { index in
          Button("Pick cat \(index + 1)") { onEvent(.tapped(index)) }
        }
      }
    }
  }

  private var label: String {
    switch state.moment {
    case .choosing:
      let count = state.cats.count
      if state.agreed != nil { return "You both picked the same cat. Hold it together to adopt." }
      if state.mine != nil, state.theirs != nil { return "You picked different cats." }
      return "\(count) cats on cushions, waiting to be chosen."
    case .adopted: return "Your cat greets you both."
    case .leaving: return "Your cat walks home."
    }
  }
}

/// The marks over the cats and the rings, drawn flat over the scene.
private struct AdoptionMarksLayer: View {
  let marks: AdoptionMarks
  let state: AdoptionSceneState
  let onEvent: @MainActor (AdoptionSceneEvent) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPressing = false

  static let mine = Color(red: 1.0, green: 0.8, blue: 0.36)
  static let theirs = Color(red: 1.0, green: 0.5, blue: 0.6)

  var body: some View {
    ZStack {
      if state.moment == .choosing {
        ForEach(Array(state.cats.indices), id: \.self) { index in
          if index < marks.heads.count { picks(at: index) }
        }
      }
      if let agreed = state.agreed, agreed < marks.bodies.count {
        rings(at: agreed)
        hold(at: agreed)
      }
    }
    .ignoresSafeArea()
    .onChange(of: state.agreed) { _, agreed in
      if agreed == nil, isPressing { release() }
    }
  }

  @ViewBuilder
  private func picks(at index: Int) -> some View {
    let mine = state.mine == index
    let theirs = state.theirs == index
    if mine || theirs {
      let size = max(marks.sizes[index] * 0.42, 18)
      HStack(spacing: size * 0.2) {
        if mine { mark("heart.fill", Self.mine, size: size) }
        if theirs { mark("pawprint.fill", Self.theirs, size: size) }
      }
      .position(x: marks.heads[index].x, y: marks.heads[index].y - size * 0.6)
      .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
      .animation(
        reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.45),
        value: state.mine
      )
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
  }

  private func mark(_ symbol: String, _ colour: Color, size: CGFloat) -> some View {
    Image(systemName: symbol)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(colour)
      .shadow(color: colour.opacity(0.85), radius: size * 0.45)
      .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
  }

  private func rings(at index: Int) -> some View {
    let radius = max(marks.sizes[index] * 1.05, 44)
    let width = max(radius * 0.09, 4)
    return ZStack {
      Circle()
        .stroke(Color.white.opacity(0.16), lineWidth: width)
        .frame(width: radius * 2, height: radius * 2)
      Circle()
        .trim(from: 0, to: state.myRing)
        .stroke(Self.mine, style: StrokeStyle(lineWidth: width, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: radius * 2, height: radius * 2)
        .shadow(color: Self.mine.opacity(0.8), radius: width)
      Circle()
        .trim(from: 0, to: state.theirRing)
        .stroke(Self.theirs, style: StrokeStyle(lineWidth: width, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: (radius + width * 1.6) * 2, height: (radius + width * 1.6) * 2)
        .shadow(color: Self.theirs.opacity(0.8), radius: width)
    }
    .position(marks.bodies[index])
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// The place to press and hold: the agreed cat itself.
  private func hold(at index: Int) -> some View {
    let radius = max(marks.sizes[index] * 1.05, 44)
    return Circle()
      .fill(Color.white.opacity(0.001))
      .frame(width: radius * 2, height: radius * 2)
      .contentShape(Circle())
      .position(marks.bodies[index])
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in
            guard !isPressing else { return }
            isPressing = true
            onEvent(.pressing(true))
          }
          .onEnded { _ in release() }
      )
      .sensoryFeedback(.impact(weight: .light), trigger: isPressing) { _, pressing in pressing }
      .accessibilityElement()
      .accessibilityLabel("The cat you both picked")
      .accessibilityHint("Hold to adopt it together.")
      .accessibilityAddTraits(.isButton)
      .accessibilityAction(named: "Hold to adopt") {
        onEvent(.pressing(true))
        Task {
          try? await Task.sleep(for: .seconds(JointCatChoice.holdLength + 0.2))
          onEvent(.pressing(false))
        }
      }
  }

  private func release() {
    guard isPressing else { return }
    isPressing = false
    onEvent(.pressing(false))
  }
}
