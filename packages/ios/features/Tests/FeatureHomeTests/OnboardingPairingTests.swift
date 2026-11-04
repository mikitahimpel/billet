import PetScene
import Testing

@testable import FeatureHome

@Suite struct OnboardingPairingTests {
  @Test func makingACodeOpensTheHeartAndThePartnerJoinsIt() {
    var flow = OnboardingPairing()
    #expect(flow.scene.moment == .resting)

    flow.observe(.creating(code: "ABCDEFGHJK", live: false, partnerHere: false))
    #expect(flow.step == .inviting(code: "ABCDEFGHJK", live: false))
    flow.observe(.creating(code: "ABCDEFGHJK", live: true, partnerHere: false))
    #expect(flow.step == .inviting(code: "ABCDEFGHJK", live: true))
    #expect(flow.scene.moment == .apart(partner: .waiting))
    #expect(flow.scene.code == "ABCDEFGHJK")
    #expect(flow.scene.mine == .left)

    flow.observe(.paired)
    #expect(flow.step == .joined(madeCode: true))
    #expect(flow.scene.moment == .together)
    #expect(flow.scene.mine == .left)
    #expect(flow.scene.code == nil)
    #expect(!flow.isFinished)

    flow.send(.joinShown)
    #expect(flow.isFinished)
  }

  @Test func thePartnerArrivingWhileStillCreatingJoinsToo() {
    var flow = OnboardingPairing()
    flow.observe(.creating(code: "ABCDEFGHJK", live: true, partnerHere: false))
    flow.observe(.creating(code: "ABCDEFGHJK", live: true, partnerHere: true))
    #expect(flow.step == .joined(madeCode: true))
  }

  @Test func enteringACodeSeesTheMirror() {
    var flow = OnboardingPairing()
    flow.send(.enterCode)
    #expect(flow.step == .enteringCode)
    #expect(flow.scene.moment == .apart(partner: .away))
    #expect(flow.scene.mine == .right)

    flow.observe(.joining)
    #expect(flow.step == .joining)
    flow.observe(.paired)
    #expect(flow.step == .joined(madeCode: false))
    #expect(flow.scene.moment == .together)
    #expect(flow.scene.mine == .right)
  }

  @Test func aRefusedCodeGoesBackToTheCode() {
    var flow = OnboardingPairing()
    flow.send(.enterCode)
    flow.observe(.joining)
    flow.observe(.unpaired)
    #expect(flow.step == .enteringCode)
  }

  @Test func aBadlyFormedCodeStaysOnTheCode() {
    var flow = OnboardingPairing()
    flow.send(.enterCode)
    // The pairing refuses it without leaving unpaired.
    flow.observe(.unpaired)
    #expect(flow.step == .enteringCode)
    flow.send(.back)
    #expect(flow.step == .welcome)
  }

  @Test func cancellingAnInviteClosesTheHeart() {
    var flow = OnboardingPairing()
    flow.observe(.creating(code: "ABCDEFGHJK", live: true, partnerHere: false))
    flow.observe(.unpaired)
    #expect(flow.step == .welcome)
    #expect(flow.scene.moment == .resting)
  }

  @Test func goingInBeforeThePartnerFinishes() {
    var flow = OnboardingPairing()
    flow.send(.goIn)
    #expect(flow.step == .welcome)
    flow.observe(.creating(code: "ABCDEFGHJK", live: true, partnerHere: false))
    flow.send(.goIn)
    #expect(flow.isFinished)
  }

  @Test func pairedWithoutACodeHereShowsNothing() {
    var flow = OnboardingPairing()
    flow.observe(.paired)
    #expect(flow.isFinished)
  }

  @Test func theJoinedMomentHoldsWhateverThePairingSays() {
    var flow = OnboardingPairing()
    flow.send(.enterCode)
    flow.observe(.joining)
    flow.observe(.paired)
    for facts in [OnboardingPairing.Facts.unpaired, .joining, .paired] {
      flow.observe(facts)
      #expect(flow.step == .joined(madeCode: false))
    }
  }

  @Test func alreadyPairedStartsDone() {
    #expect(OnboardingPairing(paired: true).isFinished)
    #expect(!OnboardingPairing(paired: false).isFinished)
  }

  @MainActor @Test func theInvitationCarriesTheCode() {
    #expect(OnboardingPairingView.invitation(code: "ABCDEFGHJK").contains("ABCDEFGHJK"))
  }
}
