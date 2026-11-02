import DesignSystem
import Foundation
import ImageIO
import Labs
import Pet
import PetScene
import SwiftUI
import WidgetBridge

/// The cat's needs over Home, as the Labs variants show them: a thought bubble over the cat,
/// words under the room, and the rings a long press pulls up. Shows nothing unless the cat's
/// needs are on.
struct HomeLifeLayer: View {
  let session: PairSession
  let scene: (any PetScene)?
  @Binding var ringsOpen: Bool
  let onFeed: () -> Void
  let onPet: () -> Void

  private var labs: WidgetFeaturesModel { session.labs }
  private var isOn: Bool { labs.isOn(LabExperiment.catLife) }

  var body: some View {
    ZStack {
      if isOn, labs.isOn(LabExperiment.lifeBubble),
        let need = LifeThought.need(session.life.drive)
      {
        LifeBubble(need: need) { answer(need) }
          .offset(x: 64, y: -150)
          .id(need)
      }
      if isOn, labs.isOn(LabExperiment.lifeChips) {
        VStack {
          Spacer()
          LifeChips(needs: session.life.state.needs)
            .padding(.bottom, Spacing.page * 2)
        }
        .allowsHitTesting(false)
      }
    }
    .calmAnimation(value: LifeThought.need(session.life.drive))
    .sheet(isPresented: $ringsOpen) {
      ZStack {
        EveningBackground()
        LifeRings(
          needs: session.life.state.needs, portrait: portrait,
          name: session.play.catName ?? "The cat")
      }
      .presentationDetents([.medium])
      .preferredColorScheme(.dark)
    }
  }

  /// The cat's still for the rings: asleep or sitting up, as the scene draws it.
  private var portrait: Image? {
    let pose: PetPose = session.life.state.asleep ? .sleeping : .proud
    guard let data = scene?.posePNG(pose),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return Image(decorative: image, scale: 1)
  }

  private func answer(_ need: PetNeed) {
    switch need {
    case .full: onFeed()
    case .loved: onPet()
    case .playful: session.played()
    case .rested: session.tuckIn()
    }
  }
}

extension View {
  /// Opens the need rings on a long press, while that variant is on.
  func lifeRingsPress(_ session: PairSession, open: Binding<Bool>) -> some View {
    simultaneousGesture(
      LongPressGesture(minimumDuration: 0.6).onEnded { _ in
        guard session.labs.isOn(LabExperiment.catLife), session.labs.isOn(LabExperiment.lifeRings)
        else { return }
        open.wrappedValue = true
      })
  }
}
