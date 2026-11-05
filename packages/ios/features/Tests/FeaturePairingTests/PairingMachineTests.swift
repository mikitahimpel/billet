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
    #expect(outputs.isEmpty)

    (state, outputs) = M.transition(state, .ticked)
    #expect(outputs == [.checkPaired(request: 2)])

    (state, _) = M.transition(state, .checked(paired: false, request: 2))
    #expect(state == .waiting(code: "ABC", expiresAt: 9, request: 2))

    (state, _) = M.transition(state, .ticked)
    (state, _) = M.transition(state, .checked(paired: true, request: 3))
    #expect(state == .paired(pairID: nil))
  }

  @Test func enteringACodeClaimsItTidied() {
    var (state, outputs) = M.transition(.initial, .codeSubmitted(" ab c "))
    #expect(outputs == [.claimInvite(code: "ABC", request: 1)])
    (state, _) = M.transition(state, .claimed(pairID: "p1", request: 1))
    #expect(state == .paired(pairID: "p1"))
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
    let (state, _) = M.transition(.claiming(request: 1), .failed(failure, request: 1))
    #expect(state == .choosing(failure: failure, request: 1))
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
    #expect(model.state == .paired(pairID: "p1"))
  }

  @Test func theCreatorSeesThePartnerArrive() async {
    var api = APIClient.offline
    api.createInvite = { () async throws(TransportError) in
      CreateInviteResponse(code: InviteCode("ABC"), expiresAt: 9)
    }
    let paired = Counter()
    api.listNotes = { (_) async throws(TransportError) in
      if paired.next() < 1 { throw .api(.notFound) }
      return ListNotesResponse(notes: [])
    }
    let model = PairingModel(api: api)
    model.createInvite()
    await model.settled()
    model.tick()
    await model.settled()
    #expect(model.state == .waiting(code: "ABC", expiresAt: 9, request: 2))
    model.tick()
    await model.settled()
    #expect(model.state == .paired(pairID: nil))
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
