import Delivery
import FeatureInbox
import Foundation
import Observation
import Persistence
import Pet
import WidgetBridge

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
    /// The saved lab flags. `nil` leaves every experiment at its default.
    var labs: WidgetFeaturesModel?
    /// Where the fake partner keeps its notes, apart from the real archive.
    var fakeArchive: NoteArchive?
    var fakeDelivery: (DemoRoom) -> NoteDelivery = { .fakePartner(device: $0.device) }
  }

  private(set) var stage = Stage.unpaired
  private(set) var failure: PairFailure?
  let labs: WidgetFeaturesModel

  /// What the screen showed before the fake partner took over, to return to when it leaves.
  @ObservationIgnored private var beforeFake: Stage?
  @ObservationIgnored private let dependencies: Dependencies
  @ObservationIgnored private var timeout: Task<Void, Never>?

  init(dependencies: Dependencies) {
    self.dependencies = dependencies
    labs = dependencies.labs ?? WidgetFeaturesModel(store: nil)
    if let room = DemoRoom.saved(in: dependencies.defaults),
      let session = makeSession(room)
    {
      stage = .paired(session)
      Task { await session.loadNotes() }
    }
    if labs.isOn(LabExperiment.fakePartner) { enterFakePartner() }
  }

  /// True while the screens show the scripted partner instead of a real room.
  var isFakePartner: Bool { beforeFake != nil }

  /// Follows the Labs switch for the fake partner.
  func fakePartnerSwitched(on: Bool) {
    if on { enterFakePartner() } else { leaveFakePartner() }
  }

  /// Shows Home with a scripted partner. The real room stays closed, and the real notes are not
  /// touched: the fake partner keeps its own.
  private func enterFakePartner() {
    guard beforeFake == nil, let archive = dependencies.fakeArchive else { return }
    let wasPairing: Stage = stage
    session?.disconnect()
    timeout?.cancel()
    let room = DemoRoom(code: "fake-partner", device: "fake-me")
    // The fake partner gets its own shop with a few things to give, so the real closet is left be.
    let shop = ShopStore(storage: .memory())
    for id in ["treat-fish", "treat-fish", "furniture-yarn"] {
      if let item = shop.catalog.item(id) {
        _ = try? shop.buy(item, transaction: shop.newTransaction())
      }
    }
    let fake = PairSession(
      room: room, delivery: dependencies.fakeDelivery(room), archive: archive,
      shop: shop, now: dependencies.now,
      isFakePartner: true, labs: labs)
    beforeFake = wasPairing
    stage = .paired(fake)
    fake.connect()
    let now = dependencies.now()
    Task {
      try? await archive.erase()
      // A little history, so the experiments that look back have something to find.
      for (component, drawing) in [(Calendar.Component.year, 0), (.month, 3)] {
        guard let then = Calendar.current.date(byAdding: component, value: -1, to: now) else {
          continue
        }
        _ = try? await archive.add(
          NoteRecord(
            direction: .received, date: then, strokes: FakePartnerDrawings.drawing(number: drawing))
        )
      }
      await fake.loadNotes()
    }
  }

  /// Leaving from a button on a fake-partner screen turns the Labs switch off as well.
  private func leaveByLabs() {
    labs.set(LabExperiment.fakePartner, on: false)
    leaveFakePartner()
  }

  private func leaveFakePartner() {
    guard let previous = beforeFake else { return }
    session?.disconnect()
    beforeFake = nil
    stage = previous
    session?.connect()
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
    guard !isFakePartner else { return leaveByLabs() }
    guard let session else { return }
    abandon(session)
  }

  /// Closes the connection, erases this device's notes and identity, and returns to pairing.
  /// Nothing on the backend changes. Returns a message if the notes could not be erased, in which
  /// case the device stays paired and reconnects.
  func logOut() async -> String? {
    guard !isFakePartner else {
      leaveByLabs()
      return nil
    }
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
      room: room, delivery: delivery, archive: dependencies.archive,
      shop: ShopStore(storage: .defaults(dependencies.defaults)), now: dependencies.now,
      labs: labs)
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
