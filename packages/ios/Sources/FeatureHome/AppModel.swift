import Delivery
import FeatureInbox
import Foundation
import Observation
import Persistence

/// Why a pairing attempt ended without a pair.
enum PairFailure: Hashable, Sendable {
  case invalidCode
  case roomFull
  case unreachable

  var message: String {
    switch self {
    case .invalidCode:
      "That isn't a billet code. Codes are 10 letters and numbers, and never use 0, 1, I, L, O or U."
    case .roomFull:
      "That code already has two people on it. Check it with your partner, or create a new pair."
    case .unreachable:
      "Couldn't reach billet. Check your connection and try again."
    }
  }
}

/// Where this device stands with its pair, and the moves between pairing and logged out.
@MainActor
@Observable
final class AppModel {
  enum Stage {
    case unpaired
    /// Connecting with a new code. `creating` waits on the code screen for the partner.
    case pairing(PairSession, creating: Bool)
    case paired(PairSession)
  }

  /// What the model reaches outside itself for.
  struct Dependencies {
    var defaults: UserDefaults
    var archive: NoteArchive
    var delivery: (DemoRoom) -> NoteDelivery?
    /// Removes whatever home-screen surfaces show and asks them to redraw.
    var clearSurfaces: @Sendable () async -> Void
    var pairingTimeout: Duration
    var now: @Sendable () -> Date = { .now }
  }

  private(set) var stage = Stage.unpaired
  private(set) var failure: PairFailure?

  @ObservationIgnored private let dependencies: Dependencies
  @ObservationIgnored private var timeout: Task<Void, Never>?

  init(dependencies: Dependencies) {
    self.dependencies = dependencies
    if let room = DemoRoom.saved(in: dependencies.defaults),
      let session = makeSession(room)
    {
      stage = .paired(session)
      Task { await session.loadNotes() }
    }
  }

  /// The session whose connection should follow the app's foreground state.
  var session: PairSession? {
    switch stage {
    case .unpaired: nil
    case .pairing(let session, _), .paired(let session): session
    }
  }

  var isPaired: Bool {
    switch stage {
    case .paired: true
    case .unpaired, .pairing: false
    }
  }

  func createPair() {
    pair(code: DemoRoom.generateCode(), creating: true)
  }

  func join(code: String) {
    guard DemoRoom.isValid(code: code) else {
      failure = .invalidCode
      return
    }
    pair(code: code, creating: false)
  }

  /// Leaves the code screen for Home. The partner can join at any time after this.
  func finishCreating() {
    guard case .pairing(let session, true) = stage, session.hasConnected else { return }
    enter(session)
  }

  /// Gives up on the pairing in progress and returns to the welcome screen.
  func cancelPairing(because failure: PairFailure? = nil) {
    guard case .pairing(let session, _) = stage else { return }
    abandon(session)
    self.failure = failure
  }

  /// Leaves a room that turned this device away, keeping its notes and device ID.
  func changeCode() {
    guard let session else { return }
    abandon(session)
  }

  /// Closes the connection, erases this device's notes and identity, and returns to pairing.
  /// Nothing on the backend changes. Returns a message if the notes could not be erased, in which
  /// case the device stays paired and reconnects.
  func logOut() async -> String? {
    guard let session else { return nil }
    session.disconnect()
    await session.savesFinished()
    do {
      try await dependencies.archive.erase()
    } catch {
      session.connect()
      return "Couldn't delete the notes on this device. Try again."
    }
    await dependencies.clearSurfaces()
    DemoRoom.logOut(in: dependencies.defaults)
    timeout?.cancel()
    failure = nil
    stage = .unpaired
    return nil
  }

  private func makeSession(_ room: DemoRoom) -> PairSession? {
    guard let delivery = dependencies.delivery(room) else { return nil }
    return PairSession(
      room: room, delivery: delivery, archive: dependencies.archive, now: dependencies.now)
  }

  private func pair(code: String, creating: Bool) {
    failure = nil
    let room = DemoRoom.pair(code: code, in: dependencies.defaults)
    guard let session = makeSession(room) else {
      DemoRoom.forget(in: dependencies.defaults)
      failure = .unreachable
      return
    }
    session.onStatus = { [weak self, weak session] status in
      guard let self, let session else { return }
      self.pairing(session, reached: status)
    }
    stage = .pairing(session, creating: creating)
    session.connect()
    Task { await session.loadNotes() }
    let limit = dependencies.pairingTimeout
    timeout = Task { [weak self] in
      try? await Task.sleep(for: limit)
      guard !Task.isCancelled, let self, !session.hasConnected else { return }
      self.cancelPairing(because: .unreachable)
    }
  }

  private func pairing(_ session: PairSession, reached status: NoteDelivery.Status) {
    guard case .pairing(let current, let creating) = stage, current === session else { return }
    switch status {
    case .connecting:
      break
    case .partnerAway:
      if !creating { enter(session) }
    case .partnerHere:
      enter(session)
    case .refused:
      cancelPairing(because: .roomFull)
    }
  }

  private func enter(_ session: PairSession) {
    timeout?.cancel()
    session.onStatus = nil
    stage = .paired(session)
  }

  private func abandon(_ session: PairSession) {
    timeout?.cancel()
    session.disconnect()
    DemoRoom.forget(in: dependencies.defaults)
    failure = nil
    stage = .unpaired
  }
}
