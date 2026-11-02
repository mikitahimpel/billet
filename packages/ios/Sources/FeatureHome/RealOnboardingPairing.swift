import FeaturePairing
import Pet
import PetScene
import SwiftUI

/// Pairing with the real backend inside the first-launch scene, on the same ``PairingModel`` as
/// ``PairingFlowView``: a made invite is checked for a claim every few seconds while it is shown.
/// Calls `onPaired` once the joined moment has been shown.
struct RealOnboardingPairing: View {
  let model: PairingModel
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let onPaired: () -> Void

  @State private var onboarding = OnboardingPairing()

  var body: some View {
    OnboardingPairingView(
      scenes: scenes, lighting: lighting, memory: OnboardingMemory(defaults: .standard),
      pairing: onboarding, failure: failure,
      actions: OnboardingPairingActions(
        create: { model.createInvite() },
        join: { model.submit(code: $0) },
        cancel: { model.cancel() },
        goIn: nil,
        tryAlone: nil),
      send: { event in
        onboarding.send(event)
        if onboarding.isFinished { onPaired() }
      }
    )
    .onChange(of: facts, initial: true) { _, facts in
      onboarding.observe(facts)
      if onboarding.isFinished { onPaired() }
    }
    .task(id: isWaiting) {
      guard isWaiting else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: PairingFlowView.checkEvery)
        guard !Task.isCancelled else { return }
        model.tick()
      }
    }
  }

  private var isWaiting: Bool {
    if case .waiting = model.state { true } else { false }
  }

  private var failure: String? {
    if case .choosing(let failure?, _) = model.state { failure.message } else { nil }
  }

  /// Where the invite is, as the scene follows it.
  private var facts: OnboardingPairing.Facts {
    switch model.state {
    case .choosing, .creating: .unpaired
    case .waiting(let code, _, _): .creating(code: code, live: true, partnerHere: false)
    case .claiming: .joining
    case .paired: .paired
    }
  }
}
