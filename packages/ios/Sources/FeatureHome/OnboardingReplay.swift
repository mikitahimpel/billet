import Delivery
import DesignSystem
import Pet
import PetScene
import SwiftUI

/// The first launch played again from Labs, over everything, without touching the pair: the
/// flight from the dark every time, nothing remembered, and a scripted partner. A made code is
/// joined a few seconds later; any well-formed typed code is joined at once.
struct OnboardingReplay: View {
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let onClose: () -> Void

  /// Bumped to play it again from the start.
  @State private var take = 0

  var body: some View {
    ReplayRun(scenes: scenes, lighting: lighting, onAgain: { take += 1 }, onClose: onClose)
      .id(take)
  }
}

/// One play of the replay.
private struct ReplayRun: View {
  let scenes: [any PetScene]
  let lighting: RoomLighting
  let onAgain: () -> Void
  let onClose: () -> Void

  @State private var pairing = OnboardingPairing()
  @State private var failure: String?
  @State private var script: Task<Void, Never>?
  @State private var adoption: AdoptionModel?
  @State private var adopter = ScriptedAdopter()
  @State private var catName: String?
  @State private var adopted = false

  /// How long the scripted partner takes to arrive after the code is made.
  static let partnerDelay = Duration.milliseconds(4_500)
  static let joinDelay = Duration.milliseconds(1_200)

  var body: some View {
    if let adoption, !adopted {
      AdoptionView(
        scenes: scenes, lighting: lighting, model: adoption, catName: catName,
        rename: { catName = $0 }, onDone: { adopted = true }
      )
      .onDisappear { adopter.stop() }
    } else if pairing.isFinished {
      CinematicOnboardingView(
        scenes: scenes, lighting: lighting, memory: nil, startsAtRest: true,
        heading: OnboardingHeading(title: "Two halves, one house", detail: "That's the opening."),
        rest: pairing.scene
      ) {
        GlassGroup {
          VStack(spacing: Spacing.small) {
            BilletButton("Play again", rank: .primary, systemImage: "arrow.counterclockwise") {
              onAgain()
            }
            BilletButton("Close", rank: .secondary, action: onClose)
          }
        }
      }
    } else {
      OnboardingPairingView(
        scenes: scenes, lighting: lighting, memory: nil, pairing: pairing, failure: failure,
        actions: OnboardingPairingActions(
          create: create, join: join, cancel: cancel, goIn: { pairing.send(.goIn) },
          tryAlone: onClose),
        send: { event in
          let wasJoined = if case .joined = pairing.step { true } else { false }
          pairing.send(event)
          if pairing.isFinished, wasJoined { startChoosing() }
        }
      )
      .onDisappear { script?.cancel() }
    }
  }

  /// The scripted partner chooses too; the choice is kept nowhere.
  private func startChoosing() {
    let adopter = adopter
    let model = AdoptionModel(send: { adopter.answer($0) }, adopt: { _ in })
    adopter.model = model
    adoption = model
  }

  private func create() {
    failure = nil
    let code = DemoRoom.generateCode()
    pairing.observe(.creating(code: code, live: true, partnerHere: false))
    run {
      try await Task.sleep(for: Self.partnerDelay)
      pairing.observe(.creating(code: code, live: true, partnerHere: true))
    }
  }

  private func join(_ code: String) {
    guard DemoRoom.isValid(code: code) else {
      failure = PairFailure.invalidCode.message
      pairing.observe(.unpaired)
      return
    }
    failure = nil
    pairing.observe(.joining)
    run {
      try await Task.sleep(for: Self.joinDelay)
      pairing.observe(.paired)
    }
  }

  private func cancel() {
    script?.cancel()
    failure = nil
    pairing.observe(.unpaired)
  }

  private func run(_ step: @escaping @MainActor () async throws -> Void) {
    script?.cancel()
    script = Task { try? await step() }
  }
}
