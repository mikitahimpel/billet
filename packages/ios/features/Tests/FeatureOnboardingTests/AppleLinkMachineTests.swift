import Foundation
import Persistence
import Testing
import Transport
import Wire

@testable import FeatureOnboarding

@Suite struct AppleLinkMachineTests {
  typealias M = AppleLinkMachine

  @Test func anUnlinkedAccountGoesThroughTheNonceAndAppleToLinked() {
    var (state, outputs) = M.transition(.idle, .appeared)
    #expect(state == .checking(request: 1))
    #expect(outputs == [.readStatus(request: 1)])

    (state, outputs) = M.transition(state, .statusRead(linked: false, request: 1))
    #expect(state == .preparing(request: 2))
    #expect(outputs == [.fetchNonce(request: 2)])

    (state, outputs) = M.transition(state, .nonceFetched("n", request: 2))
    #expect(state == .ready(nonce: "n", request: 2))
    #expect(outputs.isEmpty)

    (state, outputs) = M.transition(state, .appleCompleted(identityToken: "jwt"))
    #expect(state == .linking(request: 3))
    #expect(outputs == [.link(identityToken: "jwt", request: 3)])

    (state, outputs) = M.transition(state, .linkSaved(request: 3))
    #expect(state == .linked)
    #expect(outputs.isEmpty)
  }

  @Test func aLinkedAccountStopsAtLinkedWithoutAskingApple() {
    let (state, outputs) = M.transition(
      .checking(request: 1), .statusRead(linked: true, request: 1))
    #expect(state == .linked)
    #expect(outputs.isEmpty)
  }

  @Test func closingAppleSheetKeepsTheButton() {
    let ready = M.State.ready(nonce: "n", request: 2)
    let (state, outputs) = M.transition(ready, .appleCancelled)
    #expect(state == ready)
    #expect(outputs.isEmpty)
  }

  @Test func appleFailingShowsAFailureThatRetryRecovers() {
    var (state, _) = M.transition(.ready(nonce: "n", request: 2), .appleFailed)
    #expect(state == .failed(.appleRefused, request: 2))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .retried)
    #expect(state == .preparing(request: 3))
    #expect(outputs == [.fetchNonce(request: 3)])
  }

  @Test func anAppleIdInUseIsAFailureTheUserCanRetryWithAnotherAppleId() {
    var (state, _) = M.transition(
      .linking(request: 3), .failed(.appleIdInUse, request: 3))
    #expect(state == .failed(.appleIdInUse, request: 3))
    (state, _) = M.transition(state, .retried)
    #expect(state == .preparing(request: 4))
  }

  @Test(arguments: [SignInFailure.unavailable, .rejected, .appleRefused, .storage])
  func aFailedLinkOrNonceIsRetriedFromTheNonce(failure: SignInFailure) {
    for from in [M.State.preparing(request: 2), .linking(request: 2)] {
      let (failed, _) = M.transition(from, .failed(failure, request: 2))
      #expect(failed == .failed(failure, request: 2))
      #expect(M.transition(failed, .retried).0 == .preparing(request: 3))
    }
  }

  @Test func aStatusThatCannotBeReadIsRetriedFromTheStatus() {
    var (state, _) = M.transition(.checking(request: 1), .failed(.unavailable, request: 1))
    #expect(state == .checkFailed(request: 1))
    let outputs: [M.Output]
    (state, outputs) = M.transition(state, .retried)
    #expect(state == .checking(request: 2))
    #expect(outputs == [.readStatus(request: 2)])
  }

  @Test func aLateAnswerIsDropped() {
    let state = M.State.linking(request: 3)
    #expect(M.transition(state, .linkSaved(request: 2)).0 == state)
    #expect(M.transition(state, .failed(.unavailable, request: 2)).0 == state)
    let checking = M.State.checking(request: 2)
    #expect(M.transition(checking, .statusRead(linked: true, request: 1)).0 == checking)
  }

  @Test func everyOtherEventIsRejectedAndChangesNothing() {
    let rejected: [(M.State, [M.Event])] = [
      (
        .idle,
        [
          .retried, .statusRead(linked: true, request: 0), .appleCompleted(identityToken: "x"),
          .appleCancelled, .appleFailed, .linkSaved(request: 0), .failed(.unavailable, request: 0),
        ]
      ),
      (
        .checking(request: 1),
        [
          .appeared, .retried, .appleCompleted(identityToken: "x"),
          .appleCancelled, .appleFailed, .linkSaved(request: 1), .nonceFetched("n", request: 1),
        ]
      ),
      (
        .checkFailed(request: 1),
        [
          .appeared, .appleCompleted(identityToken: "x"), .appleFailed,
          .failed(.unavailable, request: 1), .statusRead(linked: true, request: 1),
        ]
      ),
      (
        .preparing(request: 2),
        [
          .appeared, .retried, .appleCompleted(identityToken: "x"),
          .appleCancelled, .appleFailed, .linkSaved(request: 2),
        ]
      ),
      (
        .ready(nonce: "n", request: 2),
        [
          .appeared, .retried, .linkSaved(request: 2),
          .failed(.unavailable, request: 2), .nonceFetched("m", request: 2),
          .statusRead(linked: true, request: 2),
        ]
      ),
      (
        .linking(request: 3),
        [
          .appeared, .retried, .appleCompleted(identityToken: "x"),
          .appleCancelled, .appleFailed, .nonceFetched("n", request: 3),
        ]
      ),
      (
        .linked,
        [
          .appeared, .retried, .appleCompleted(identityToken: "x"), .appleFailed,
          .linkSaved(request: 0), .failed(.unavailable, request: 0), .nonceFetched("n", request: 0),
        ]
      ),
      (
        .failed(.rejected, request: 2),
        [
          .appeared, .appleCompleted(identityToken: "x"),
          .appleCancelled, .appleFailed, .linkSaved(request: 2), .failed(.unavailable, request: 2),
        ]
      ),
    ]
    for (state, events) in rejected {
      for event in events {
        let (next, outputs) = M.transition(state, event)
        #expect(next == state, "\(state) took \(event)")
        #expect(outputs.isEmpty, "\(state) ran work for \(event)")
      }
    }
  }

  @Test func eachFailureHasItsOwnWords() {
    let all: [SignInFailure] = [.appleRefused, .rejected, .unavailable, .storage, .appleIdInUse]
    #expect(Set(all.map(\.linkMessage)).count == all.count)
  }
}

@Suite @MainActor struct AppleLinkModelTests {
  nonisolated static let nonce = String(repeating: "a", count: 43)

  static func api(
    linked: Bool = false,
    link: @escaping @Sendable () throws(TransportError) -> AccountResponse = {
      AccountResponse(userId: UserId("u1"), linked: true)
    }
  ) -> APIClient {
    var api = APIClient.offline
    api.account = { () async throws(TransportError) in
      AccountResponse(userId: UserId("u1"), linked: linked)
    }
    api.authChallenge = { () async throws(TransportError) in
      AuthChallengeResponse(nonce: AuthNonce(nonce), expiresAt: 1)
    }
    api.linkApple = { (_) async throws(TransportError) in try link() }
    return api
  }

  @Test func linkingAnUnlinkedAccountEndsLinked() async {
    let model = AppleLinkModel(api: Self.api())
    model.appeared()
    await model.settled()
    #expect(model.state == .ready(nonce: Self.nonce, request: 2))
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .linked)
  }

  @Test func aLinkedAccountNeverShowsTheButton() async {
    let model = AppleLinkModel(api: Self.api(linked: true))
    model.appeared()
    await model.settled()
    #expect(model.state == .linked)
  }

  @Test func anAppleIdInUseSaysSoAndLeavesTheAccountUnlinked() async {
    let model = AppleLinkModel(
      api: Self.api(link: { () throws(TransportError) in throw .api(.appleIdInUse) }))
    model.appeared()
    await model.settled()
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .failed(.appleIdInUse, request: 3))
  }

  @Test func theNetworkBeingDownIsAnUnavailableFailure() async {
    let model = AppleLinkModel(
      api: Self.api(link: { () throws(TransportError) in throw .network("offline") }))
    model.appeared()
    await model.settled()
    model.appleCompleted(identityToken: "jwt")
    await model.settled()
    #expect(model.state == .failed(.unavailable, request: 3))
  }

  @Test func theStatusBeingUnreadableAllowsARetry() async {
    let model = AppleLinkModel(api: .offline)
    model.appeared()
    await model.settled()
    #expect(model.state == .checkFailed(request: 1))
  }
}
