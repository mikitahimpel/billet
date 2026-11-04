import DesignSystem
import Foundation
import Labs
import Pet
import SwiftUI
import WidgetBridge

/// The cat's needs over Home, as the Labs variants show them: a thought bubble over the cat,
/// words under the room, and the needs card a long press pulls up. Shows nothing unless the cat's
/// needs are on.
struct HomeLifeLayer: View {
  let session: PairSession
  @Binding var ringsOpen: Bool
  /// The cat's needs, for the card a long press pulls up.
  let mood: CatNeedsSnapshot
  /// Answers a need, from the thought bubble or the card.
  let onAnswer: (PetNeed) -> Void

  private var labs: WidgetFeaturesModel { session.labs }

  var body: some View {
    ZStack {
      if labs.isOn(LabExperiment.lifeBubble),
        let need = LifeThought.need(session.life.drive)
      {
        LifeBubble(need: need) { onAnswer(need) }
          .offset(x: 64, y: -150)
          .id(need)
      }
      if labs.isOn(LabExperiment.lifeChips) {
        VStack {
          Spacer()
          LifeChips(needs: session.life.state.needs)
            .padding(.bottom, Spacing.page * 2)
        }
        .allowsHitTesting(false)
      }
    }
    .calmAnimation(value: LifeThought.need(session.life.drive))
    .needsSheet(isPresented: $ringsOpen, mood: mood, onAnswer: onAnswer)
  }
}

extension View {
  /// Opens the needs card on a long press, while that variant is on.
  func lifeRingsPress(_ session: PairSession, open: Binding<Bool>) -> some View {
    simultaneousGesture(
      LongPressGesture(minimumDuration: 0.6).onEnded { _ in
        guard session.labs.isOn(LabExperiment.lifeRings) else { return }
        open.wrappedValue = true
      })
  }
}
