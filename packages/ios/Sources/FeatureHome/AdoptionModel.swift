import Foundation
import Observation
import Pet
import PetScene

/// Choosing the cat together on this phone: the joint choice, fed this phone's touches and the
/// partner's moves, the moves it sends back, and what the scene shows.
@MainActor
@Observable
final class AdoptionModel {
  enum Moment: Equatable {
    case choosing
    case adopted
    case leaving
  }

  let cats = AdoptionCat.allCases
  private(set) var choice: JointCatChoice
  private(set) var moment = Moment.choosing
  /// The clock the rings fill by, stepped while a finger is down.
  private(set) var now: Date

  @ObservationIgnored private let send: (AdoptionMove) -> Void
  @ObservationIgnored private let adopt: (AdoptionCat) -> Void
  @ObservationIgnored private let clock: () -> Date

  /// `send` tells the partner a move; `adopt` keeps the adopted cat.
  init(
    partnerHere: Bool = true, send: @escaping (AdoptionMove) -> Void,
    adopt: @escaping (AdoptionCat) -> Void, clock: @escaping () -> Date = Date.init
  ) {
    choice = JointCatChoice(partnerHere: partnerHere)
    self.send = send
    self.adopt = adopt
    self.clock = clock
    now = clock()
  }

  var adopted: AdoptionCat? { choice.adopted }

  /// Whether the rings need the clock to move.
  var isTicking: Bool { choice.isHolding || choice.partnerIsHolding }

  var scene: AdoptionSceneState {
    AdoptionSceneState(
      cats: cats.map(\.choice), mine: choice.mine.flatMap(cats.firstIndex),
      theirs: choice.theirs.flatMap(cats.firstIndex), myRing: choice.myRing(at: now),
      theirRing: choice.theirRing(at: now), adopted: choice.adopted.flatMap(cats.firstIndex),
      moment: sceneMoment)
  }

  private var sceneMoment: AdoptionSceneState.Moment {
    switch moment {
    case .choosing: .choosing
    case .adopted: .adopted
    case .leaving: .leaving
    }
  }

  // MARK: - This phone

  func tapped(_ index: Int) {
    guard moment == .choosing, cats.indices.contains(index) else { return }
    let cat = cats[index]
    // Tapping your own pick again, while the partner has another, keeps it.
    forward(choice.pick(cat))
  }

  func pressing(_ down: Bool) {
    now = clock()
    forward(choice.hold(down, at: now))
  }

  func tick() {
    now = clock()
    forward(choice.tick(at: now))
  }

  /// The adopted cat walks out.
  func goHome() {
    guard moment == .adopted else { return }
    moment = .leaving
  }

  // MARK: - The partner

  func received(_ move: AdoptionMove) {
    now = clock()
    forward(choice.received(move, at: now))
  }

  func partnerPresence(_ here: Bool) {
    choice.partnerPresence(here)
  }

  private func forward(_ moves: [AdoptionMove]) {
    for move in moves { send(move) }
    if let cat = choice.adopted, moment == .choosing {
      moment = .adopted
      adopt(cat)
    }
  }
}

/// FAKE. The scripted partner for a replay, with nothing behind it: it answers this phone's
/// moves with the fake adopter's replies, on a timer.
@MainActor
final class ScriptedAdopter {
  private var adopter = FakeAdopter()
  private var replies: Task<Void, Never>?
  weak var model: AdoptionModel?

  func answer(_ move: AdoptionMove) {
    let answer = adopter.answer(move)
    guard !answer.isEmpty else { return }
    replies?.cancel()
    replies = Task { [weak self] in
      var waited = Duration.zero
      for reply in answer {
        try? await Task.sleep(for: reply.after - waited)
        waited = reply.after
        guard !Task.isCancelled else { return }
        self?.model?.received(reply.move)
      }
    }
  }

  func stop() { replies?.cancel() }
}
