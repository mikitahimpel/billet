import Foundation
import Testing
import Transport
import Wire

@testable import FeaturePairing

@Suite struct PairingMachineTests {
  typealias M = PairingMachine

  @Test func creatingAnInviteWaitsForThePartner() {
    var (state, outputs) = M.transition(.initial, .createRequested)
    #expect(state == .creating(request: 1))
    #expect(outputs == [.createInvite(request: 1)])

    (state, outputs) = M.transition(state, .created(code: "ABC", expiresAt: 9, request: 1))
    #expect(state == .waiting(code: "ABC", expiresAt: 9, request: 1))
    #expect(outputs == [.keepInvite(KeptInvite(code: "ABC", expiresAt: 9))])

    (state, outputs) = M.transition(state, .ticked)
    #expect(outputs == [.checkPaired(request: 2)])

    (state, _) = M.transition(state, .checked(paired: false, request: 2))
    #expect(state == .waiting(code: "ABC", expiresAt: 9, request: 2))

    (state, _) = M.transition(state, .ticked)
    (state, outputs) = M.transition(state, .checked(paired: true, request: 3))
    #expect(state == .paired(.inviter))
    #expect(outputs == [.forgetInvite])
  }

  @Test func aShownInviteIsForgottenOnlyWhenItEnds() {
    let waiting = M.State.waiting(code: "ABC", expiresAt: 9, request: 2)
    #expect(M.transition(waiting, .cancelled).1 == [.forgetInvite])
    #expect(M.transition(waiting, .failed(.signedOut, request: 2)).1 == [.forgetInvite])
    #expect(M.transition(waiting, .failed(.unavailable, request: 2)).1.isEmpty)
    #expect(M.transition(waiting, .checked(paired: false, request: 2)).1.isEmpty)
    #expect(M.transition(.creating(request: 1), .cancelled).1.isEmpty)
  }

  @Test func enteringACodeClaimsItTidied() {
    var (state, outputs) = M.transition(.initial, .codeSubmitted(" ab c "))
    #expect(outputs == [.claimInvite(code: "ABC", request: 1)])
    (state, _) = M.transition(state, .claimed(pairID: "p1", request: 1))
    #expect(state == .paired(.joiner(pairID: "p1")))
  }

  @Test func anEmptyCodeIsInvalidWithoutACall() {
    let (state, outputs) = M.transition(.initial, .codeSubmitted("  "))
    #expect(state == .choosing(failure: .invalidCode, request: 0))
    #expect(outputs.isEmpty)
  }

  @Test(arguments: [
    (TransportError.api(.invalidInvite), PairingFailure.invalidCode),
    (.api(.alreadyPaired), .alreadyPaired),
    (.api(.unauthorized), .signedOut),
    (.api(.unavailable), .unavailable),
    (.network("x"), .unavailable),
    (.status(500), .unavailable),
  ])
  func failuresAreDistinct(error: TransportError, failure: PairingFailure) {
    #expect(PairingFailure(error) == failure)
    let (state, _) = M.transition(.creating(request: 1), .failed(failure, request: 1))
    #expect(state == .choosing(failure: failure, request: 1))
  }

  @Test func aClaimTheServerCallsAlreadyPairedIsTheJoinersPair() {
    let (state, outputs) = M.transition(.claiming(request: 1), .failed(.alreadyPaired, request: 1))
    #expect(state == .paired(.joiner(pairID: nil)))
    #expect(outputs.isEmpty)
    #expect(
      M.transition(.claiming(request: 1), .failed(.invalidCode, request: 1)).0
        == .choosing(failure: .invalidCode, request: 1))
  }

  @Test func invalidAndAlreadyPairedReadDifferently() {
    #expect(
      PairingFailure.invalidCode.message != PairingFailure.alreadyPaired.message)
  }

  @Test func aStaleResultChangesNothing() {
    let waiting = M.State.waiting(code: "ABC", expiresAt: 9, request: 3)
    #expect(M.transition(waiting, .checked(paired: true, request: 2)).0 == waiting)
    #expect(M.transition(waiting, .failed(.unavailable, request: 1)).0 == waiting)
  }

  @Test func aFailedCheckKeepsTheInviteButALostSessionEndsIt() {
    let waiting = M.State.waiting(code: "ABC", expiresAt: 9, request: 2)
    #expect(M.transition(waiting, .failed(.unavailable, request: 2)).0 == waiting)
    #expect(
      M.transition(waiting, .failed(.signedOut, request: 2)).0
        == .choosing(failure: .signedOut, request: 2))
  }

  @Test func cancellingReturnsToChoosingAndDropsALateAnswer() {
    var (state, _) = M.transition(.initial, .createRequested)
    (state, _) = M.transition(state, .cancelled)
    #expect(state == .choosing(failure: nil, request: 2))
    let late = M.transition(state, .created(code: "ABC", expiresAt: 9, request: 1))
    #expect(late.0 == state)
  }
}

@Suite @MainActor struct PairingModelTests {
  @Test func claimingAnUnknownCodeShowsInvalid() async {
    var api = APIClient.offline
    api.claimInvite = { (_) async throws(TransportError) in throw .api(.invalidInvite) }
    let model = PairingModel(api: api)
    model.submit(code: "nope")
    await model.settled()
    #expect(model.state == .choosing(failure: .invalidCode, request: 1))
  }

  @Test func claimingAGoodCodePairs() async {
    var api = APIClient.offline
    api.claimInvite = { (_) async throws(TransportError) in
      ClaimInviteResponse(pairId: PairId("p1"))
    }
    let model = PairingModel(api: api)
    model.submit(code: "good")
    await model.settled()
    #expect(model.state == .paired(.joiner(pairID: "p1")))
  }

  @Test func theCreatorSeesThePartnerArrive() async {
    var api = APIClient.offline
    api.createInvite = { () async throws(TransportError) in
      CreateInviteResponse(code: InviteCode("ABC"), expiresAt: 9)
    }
    let paired = Counter()
    api.pair = { () async throws(TransportError) in
      if paired.next() < 1 { throw .api(.notFound) }
      return PairResponse(pairId: PairId("p1"), members: [UserId("u1"), UserId("u2")])
    }
    let model = PairingModel(api: api)
    model.createInvite()
    await model.settled()
    model.tick()
    await model.settled()
    #expect(model.state == .waiting(code: "ABC", expiresAt: 9, request: 2))
    model.tick()
    await model.settled()
    #expect(model.state == .paired(.inviter))
  }

  @Test func aRelaunchShowsTheKeptInviteUntilItRunsOut() async {
    let kept = Kept(KeptInvite(code: "ABC", expiresAt: 10_000))
    var api = APIClient.offline
    api.createInvite = { () async throws(TransportError) in
      Issue.record("a kept invite is not made again")
      return CreateInviteResponse(code: InviteCode("NEW"), expiresAt: 99_000)
    }
    let model = PairingModel(api: api, invites: kept.keeper, now: Date(timeIntervalSince1970: 9))
    #expect(model.state == .waiting(code: "ABC", expiresAt: 10_000, request: 0))
    model.cancel()
    await model.settled()
    #expect(kept.invite == nil)

    let expired = Kept(KeptInvite(code: "ABC", expiresAt: 10_000))
    let late = PairingModel(api: api, invites: expired.keeper, now: Date(timeIntervalSince1970: 10))
    #expect(late.state == .initial)
  }

  @Test func aCreatedInviteIsKept() async {
    let kept = Kept(nil)
    var api = APIClient.offline
    api.createInvite = { () async throws(TransportError) in
      CreateInviteResponse(code: InviteCode("ABC"), expiresAt: 9)
    }
    let model = PairingModel(api: api, invites: kept.keeper)
    model.createInvite()
    await model.settled()
    #expect(kept.invite == KeptInvite(code: "ABC", expiresAt: 9))
  }

  @Test func anAlreadyPairedAccountIsToldSo() async {
    var api = APIClient.offline
    api.createInvite = { () async throws(TransportError) in throw .api(.alreadyPaired) }
    let model = PairingModel(api: api)
    model.createInvite()
    await model.settled()
    #expect(model.state == .choosing(failure: .alreadyPaired, request: 1))
  }
}

@MainActor
final class Kept {
  var invite: KeptInvite?
  init(_ invite: KeptInvite?) { self.invite = invite }

  var keeper: InviteKeeper {
    InviteKeeper(load: { self.invite }, keep: { self.invite = $0 })
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  func next() -> Int {
    lock.withLock {
      count += 1
      return count - 1
    }
  }
}
