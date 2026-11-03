import Foundation
import Observation
import Pet

/// The cat's brain on this phone: a ``CatBrainRunner`` fed by the pet's life, on the life's clock,
/// so the debug clock speeds the brain up with the needs. It publishes a frame only when the brain
/// moves, a few times a second at most.
@MainActor
@Observable
public final class CatBrainModel {
  /// What the room's cat should show now, or nil before the brain has started.
  public private(set) var frame: CatBrainFrame?
  /// The last moves and utility scores, for the debug overlay.
  public private(set) var transitions: [CatBrainTransition] = []
  public private(set) var scores: [CatUtilityScore] = []
  public private(set) var personality = CatPersonality.even
  /// The personality it was born with, before experience moved it.
  public private(set) var nature = CatPersonality.even
  public private(set) var memory = CatMemory()
  /// Who did something for the cat last, and how long the one seen least is away, in hours.
  public private(set) var lastBy: String?
  public private(set) var awayHours = 0.0
  /// The toys this phone played with lately, the newest first. They stay on this phone.
  public private(set) var recentToys: [CatToy] = []

  @ObservationIgnored private let life: PetLifeModel
  @ObservationIgnored private var runner: CatBrainRunner?
  @ObservationIgnored private var seed: UInt64 = 1
  /// What kind of cat it is at heart, fixed for life.
  public private(set) var temperament: CatTemperament?
  @ObservationIgnored private var room = RoomAffordances.empty
  @ObservationIgnored private var weather = ViewWeather.clear
  @ObservationIgnored private var known = Set<UUID>()

  public init(life: PetLifeModel) {
    self.life = life
  }

  /// The pet's seed, from what both phones share: the pair's room and the adopted cat.
  public static func seed(pair: String, cat: CatChoice) -> UInt64 {
    StableHash.of("\(pair)/\(cat.model.rawValue)/\(cat.coat.rawValue)")
  }

  /// Starts again for a different pet. The same pet keeps the brain as it is.
  public func setSeed(_ seed: UInt64, temperament: CatTemperament? = nil) {
    guard seed != self.seed || temperament != self.temperament else { return }
    self.seed = seed
    self.temperament = temperament
    runner = nil
    tick()
  }

  /// What the room on show offers the cat.
  public func setRoom(_ room: RoomAffordances, weather: ViewWeather) {
    guard room != self.room || weather != self.weather else { return }
    self.room = room
    self.weather = weather
    runner?.setRoom(room, weather: weather)
    tick()
  }

  /// This phone's own touch, shown over the brain without changing it.
  public func setLive(_ interaction: CatInteraction?) {
    guard runner?.live != interaction else { return }
    runner?.live = interaction
    if case .toy(let toy) = interaction {
      recentToys.removeAll { $0 == toy }
      recentToys.insert(toy, at: 0)
      if recentToys.count > 3 { recentToys.removeLast() }
    }
    publish()
  }

  /// Folds the brain up to the life's clock and publishes what changed.
  public func tick() {
    let now = life.now.timeIntervalSince1970
    let events = life.log.all + life.debugEvents
    // The clock went back, as when the debug clock returns to real time: start again.
    if let runner, now < runner.brain.time - 1 { self.runner = nil }
    if var runner {
      let fresh = events.filter { !known.contains($0.id) }
      if !fresh.isEmpty { runner.receive(fresh, now: now) }
      runner.advance(to: now)
      self.runner = runner
    } else {
      runner = CatBrainRunner(
        events: events, now: now, context: life.context, seed: seed, temperament: temperament,
        room: room,
        weather: weather, lifeConfig: life.config)
    }
    known = Set(events.map(\.id))
    publish()
  }

  private func publish() {
    guard let runner else { return }
    let frame = runner.frame
    guard frame != self.frame else { return }
    self.frame = frame
    transitions = runner.brain.transitions
    scores = runner.brain.scores
    personality = runner.brain.personality
    nature = runner.brain.nature
    memory = runner.brain.memory
    lastBy = runner.brain.lastBy
    awayHours = runner.brain.awayHours(at: runner.brain.time)
  }

  /// Seconds of real time to the next decision, kept between a twentieth of a second and one.
  private var wait: Double {
    guard let runner else { return 0.25 }
    let ahead = (runner.brain.nextDecision - life.now.timeIntervalSince1970) / max(life.speed, 1)
    return min(max(ahead, 0.05), 1)
  }

  /// Ticks at each decision until cancelled.
  public func run() async {
    while !Task.isCancelled {
      tick()
      try? await Task.sleep(for: .seconds(wait))
    }
  }
}
