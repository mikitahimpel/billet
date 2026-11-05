import Pet
import Testing

@testable import PetSceneReality

/// The clip the rig plays never twitches: whatever the room asks for frame by frame, the clip
/// shown changes no faster than the gate allows, a clip asked for a frame or two never shows, and
/// a real walk still starts at once.
@Suite struct CatClipGateTests {
  /// The clips the room asked for on the Simulator with the Detailed cat (before this gate,
  /// brain on, Window Seat), from the CatMotion log: each from its time until the next.
  static let logged: [(String, Double)] = [
    ("happy", 0.533),
    ("walk", 3.159),
    ("sit", 4.080),
    ("walk", 4.121),
    ("sit", 4.271),
    ("perk", 9.934),
    ("idle", 10.649),
    ("headbutt", 10.949),
    ("happy", 12.749),
    ("idle", 14.149),
    ("sit", 14.449),
    ("headbutt", 14.949),
    ("sit", 14.983),
    ("perk", 19.599),
    ("idle", 20.113),
    ("reachUp", 20.414),
    ("idle", 22.614),
    ("sit", 22.932),
    ("reachUp", 23.414),
    ("crouchWiggle", 24.462),
    ("walk", 24.502),
    ("crouchWiggle", 24.531),
    ("walk", 24.576),
    ("crouchWiggle", 24.615),
    ("pounce", 29.447),
    ("walk", 30.941),
    ("sit", 31.407),
    ("happy", 39.491),
    ("look", 42.886),
    ("crouchWiggle", 43.886),
    ("idle", 44.803),
    ("perk", 45.127),
    ("crouchWiggle", 45.691),
    ("idle", 46.386),
    ("pounce", 46.686),
    ("happy", 47.886),
    ("idle", 49.086),
    ("walk", 49.412),
    ("sit", 50.086),
    ("sniff", 50.886),
    ("idle", 52.803),
    ("sniff", 52.886),
    ("idle", 55.103),
    ("crouchWiggle", 55.636),
    ("sit", 57.020),
    ("crouchWiggle", 57.336),
    ("pounce", 60.657),
    ("look", 62.136),
    ("crouchWiggle", 63.136),
    ("idle", 64.053),
    ("pounce", 64.353),
    ("perk", 65.553),
    ("crouchWiggle", 66.153),
    ("idle", 66.853),
    ("happy", 67.153),
    ("idle", 68.353),
    ("walk", 68.653),
    ("sit", 68.870),
    ("eat", 74.809),
    ("sit", 80.826),
    ("walk", 135.274),
    ("sit", 135.438),
    ("walk", 135.721),
    ("sniff", 136.454),
    ("idle", 137.675),
    ("sniff", 138.254),
    ("idle", 140.454),
    ("sniff", 140.740),
    ("sit", 142.545),
    ("sniff", 142.804),
    ("idle", 142.954),
    ("sniff", 143.554),
    ("walk", 144.004),
    ("sit", 144.204),
    ("walk", 144.221),
    ("sit", 144.388),
    ("crouchWiggle", 159.812),
    ("sit", 161.678),
    ("crouchWiggle", 161.945),
    ("pounce", 163.695),
    ("walk", 164.928),
    ("sniff", 165.462),
    ("idle", 167.678),
    ("sniff", 168.262),
    ("walk", 169.717),
    ("sit", 170.045),
    ("walk", 170.062),
    ("sit", 170.195),
    ("walk", 170.212),
    ("sit", 170.262),
    ("pounce", 208.284),
    ("bat", 209.782),
    ("sit", 211.235),
    ("bat", 211.782),
    ("walk", 212.285),
    ("sit", 212.948),
    ("walk", 212.965),
    ("sit", 213.098),
    ("walk", 213.115),
    ("sit", 213.198),
  ]

  /// What the gate shows at 60 frames a second for wishes each held until the next one, as
  /// (clip, from, to) runs.
  static func shown(_ wishes: [(CatAction, Double)], until end: Double) -> [(
    CatAction, Double, Double
  )] {
    var gate = CatClipGate()
    var runs: [(CatAction, Double, Double)] = []
    var index = 0
    var t = wishes.first?.1 ?? 0
    while t < end {
      while index + 1 < wishes.count, wishes[index + 1].1 <= t { index += 1 }
      let action = gate.choose(wishes[index].0, at: t)
      if runs.last?.0 == action {
        runs[runs.count - 1].2 = t
      } else {
        if !runs.isEmpty { runs[runs.count - 1].2 = t }
        runs.append((action, t, t))
      }
      t += 1.0 / 60
    }
    return runs
  }

  @Test func theLoggedDayNeverTwitches() throws {
    let wishes = try Self.logged.map { (try #require(CatAction(rawValue: $0.0)), $0.1) }
    let end = try #require(wishes.last?.1) + 2
    let runs = Self.shown(wishes, until: end)
    // Every clip but the last plays its minimum, or the debounce when the cat sets off or stops.
    for (i, run) in runs.dropLast().enumerated() {
      let next = runs[i + 1].0
      let least =
        CatClipGate.travels(run.0) || CatClipGate.travels(next)
        ? CatClipGate.debounce : CatClipGate.minimumDwell
      #expect(run.2 - run.1 >= least - 0.02, "\(run.0) for \(run.2 - run.1) s before \(next)")
    }
    // A clip asked for for less than the debounce never shows while it is asked for.
    for (i, wish) in wishes.dropLast().enumerated()
    where wishes[i + 1].1 - wish.1 < CatClipGate.debounce {
      #expect(
        !runs.contains { $0.0 == wish.0 && $0.1 >= wish.1 && $0.1 < wishes[i + 1].1 },
        "\(wish.0) at \(wish.1) shows for a moment")
    }
  }

  @Test func aFrameLongWishNeverShows() {
    let blip: [(CatAction, Double)] = [
      (.sit, 0), (.walk, 4), (.sit, 4 + 1.0 / 60), (.headbutt, 6),
      (.sit, 6.033),
    ]
    let runs = Self.shown(blip, until: 8)
    #expect(runs.map(\.0) == [.sit])
  }

  @Test func aRealWalkStartsAtOnceAndASitWaits() throws {
    let runs = Self.shown([(.sit, 0), (.loaf, 0.1), (.walk, 0.3)], until: 3)
    // The loaf asked for after a tenth of a second waits for the sit's minimum, and the walk
    // after it starts within the debounce.
    let walk = try #require(runs.first { $0.0 == .walk })
    #expect(walk.1 <= 0.3 + CatClipGate.debounce + 1.0 / 60 + 1e-6)
    #expect(!runs.contains { $0.0 == .loaf })
  }

  @Test func beingPickedUpSwitchesAtOnce() {
    var gate = CatClipGate()
    _ = gate.choose(.sit, at: 0)
    #expect(gate.choose(.dangle, at: 0.05, force: true) == .dangle)
  }
}
