import DesignSystem
import Pet
import PetScene
import SwiftUI

/// Choosing the cat together, after the pair is made: the cats on their cushions, each pick
/// marked for both, a press and hold together to adopt, a name, and then the cat walks home.
struct AdoptionView: View {
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let model: AdoptionModel
  /// The cat's name as the room holds it, which either partner may change: the last edit wins.
  let catName: String?
  let rename: (String) -> Void
  /// The cat has walked out: time for the room.
  let onDone: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var name = ""
  @FocusState private var naming: Bool
  @State private var adoptions = 0

  var body: some View {
    ZStack {
      if let scene = sceneView {
        scene
          .environment(\.petSceneLighting, lighting)
          .ignoresSafeArea()
      } else {
        EveningBackground()
        fallbackCats
      }
      overlay
    }
    .preferredColorScheme(.dark)
    .sensoryFeedback(.success, trigger: adoptions)
    .onChange(of: model.adopted) { _, adopted in if adopted != nil { adoptions += 1 } }
    .onChange(of: catName, initial: true) { _, catName in
      if let catName, !naming { name = catName }
    }
    .task(id: model.isTicking) {
      while model.isTicking, !Task.isCancelled {
        model.tick()
        try? await Task.sleep(for: .milliseconds(33))
      }
      model.tick()
    }
  }

  private var sceneView: AnyView? {
    let state = model.scene
    for scene in scenes {
      if let view = scene.makeAdoptionScene(state: state, onEvent: { handle($0) }) {
        return view
      }
    }
    return nil
  }

  private func handle(_ event: AdoptionSceneEvent) {
    switch event {
    case .tapped(let index): model.tapped(index)
    case .pressing(let down): model.pressing(down)
    case .left: onDone()
    }
  }

  // MARK: - Words and controls

  private var overlay: some View {
    VStack(spacing: Spacing.small) {
      HeadingWords(heading: heading)
        .padding(.top, Spacing.wide)
        .padding(.horizontal, Spacing.medium)
      Spacer(minLength: 0)
      if model.moment == .choosing { legend }
    }
    // The full width, so the name field and button below are not as narrow as the heading.
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(model.moment == .leaving ? 0 : 1)
    .animation(.easeOut(duration: 0.5), value: model.moment)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if model.moment == .adopted {
        naming(for: model.adopted)
          .padding(.horizontal, Spacing.medium)
          .padding(.vertical, Spacing.small)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.5), value: model.moment)
    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
  }

  private var legend: some View {
    // Side by side while they fit, one over the other when the text is large.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.medium) { legendItems }
      VStack(spacing: Spacing.hair) { legendItems }
    }
    .billetType(.caption)
    .padding(.horizontal, Spacing.medium)
    .padding(.bottom, Spacing.small)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var legendItems: some View {
    Label("You", systemImage: "heart.fill")
      .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.36))
    Label(
      model.choice.partnerHere ? "Your person" : "Your person, away", systemImage: "pawprint.fill"
    )
    .foregroundStyle(Color(red: 1.0, green: 0.5, blue: 0.6))
  }

  private func naming(for cat: AdoptionCat?) -> some View {
    GlassGroup {
      VStack(spacing: Spacing.small) {
        TextField("Give them a name", text: $name)
          .billetType(.body)
          .multilineTextAlignment(.center)
          .wordsCapitalized()
          .submitLabel(.done)
          .focused($naming)
          .padding(.vertical, Spacing.small)
          .padding(.horizontal, Spacing.medium)
          .frame(maxWidth: .infinity, minHeight: Target.row)
          .background(.white.opacity(0.08), in: Capsule())
          .onSubmit { commitName() }
          .onChange(of: naming) { _, focused in if !focused { commitName() } }
          .accessibilityLabel("Name for \(cat?.title ?? "your cat")")
        BilletButton("Take them home", rank: .primary, systemImage: "house.fill") {
          commitName()
          naming = false
          model.goHome()
          // Without a scene, nothing walks out.
          if sceneView == nil { onDone() }
        }
      }
    }
  }

  private func commitName() {
    guard let clean = CatName.clean(name), clean != catName else { return }
    rename(clean)
  }

  private var heading: OnboardingHeading {
    switch model.moment {
    case .adopted, .leaving:
      return OnboardingHeading(
        title: "Meet your cat", detail: "Either of you can name them. You can change it later.")
    case .choosing:
      let choice = model.choice
      if let cat = choice.agreed {
        return OnboardingHeading(
          title: "You both picked \(cat.title)",
          detail: nature(of: cat) + "Hold them together until your rings fill.")
      }
      if choice.bid != nil {
        return OnboardingHeading(
          title: "Two favourites",
          detail: "They're making their case. Pick again whenever you like.")
      }
      if let mine = choice.mine {
        return OnboardingHeading(
          title: "Good taste", detail: nature(of: mine) + "Waiting for your person to pick too.")
      }
      return OnboardingHeading(
        title: "Choose your cat together", detail: "Tap the one you'd love to bring home.")
    }
  }

  /// What kind of cat `cat` is, as the start of a heading's detail, or nothing when not known.
  private func nature(of cat: AdoptionCat) -> String {
    guard let temperament = model.temperament(cat) else { return "" }
    return "\(temperament.title): \(temperament.line) "
  }

  /// Without a 3D scene: the cats as buttons.
  private var fallbackCats: some View {
    VStack(spacing: Spacing.small) {
      Spacer()
      ForEach(Array(model.cats.enumerated()), id: \.offset) { index, cat in
        let mine = model.choice.mine == cat
        let theirs = model.choice.theirs == cat
        BilletButton(
          cat.title.capitalized + (model.temperament(cat).map { ", \($0.title)" } ?? "")
            + (mine ? " ♥" : "") + (theirs ? " 🐾" : ""),
          rank: mine ? .primary : .secondary
        ) { model.tapped(index) }
      }
      if model.choice.agreed != nil {
        BilletButton("Adopt together", rank: .primary, systemImage: "heart.circle.fill") {}
          .simultaneousGesture(
            DragGesture(minimumDistance: 0)
              .onChanged { _ in if !model.choice.isHolding { model.pressing(true) } }
              .onEnded { _ in model.pressing(false) })
      }
      Spacer()
    }
    .padding(.horizontal, Spacing.medium)
  }
}

extension View {
  fileprivate func wordsCapitalized() -> some View {
    #if os(iOS)
      textInputAutocapitalization(.words)
    #else
      self
    #endif
  }
}
