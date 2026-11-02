import Foundation
import Testing

@testable import Pet

@Suite("CatBehaviour")
struct CatBehaviourTests {
  /// A model with every clip: loops for the bases, short one-shots for the rest.
  private static let full: [CatAction: CatClipInfo] = {
    var clips: [CatAction: CatClipInfo] = [:]
    for action in CatAction.allCases {
      switch action {
      case .idle, .walk, .crouchWiggle, .eat:
        clips[action] = CatClipInfo(duration: 4, loops: true, base: .stand)
      case .sleep: clips[action] = CatClipInfo(duration: 6, loops: true, base: .sleep)
      case .sit, .blink, .look, .tailFlick, .happy, .knead:
        clips[action] = CatClipInfo(duration: 4, loops: true, base: .sit)
      case .pounce, .stretch: clips[action] = CatClipInfo(duration: 1.5, loops: false, base: .stand)
      case .yawn, .groom, .slowBlink, .perk:
        clips[action] = CatClipInfo(duration: 2, loops: false, base: .sit)
      }
    }
    return clips
  }()

  /// Cues sampled every 1/30 s from `start` for `seconds`, as (time, action) at each change.
  private func run(
    _ behaviour: inout CatBehaviour, from start: Double = 0, for seconds: Double,
    mode: CatBehaviour.Mode = .free
  ) -> [(Double, CatAction)] {
    var changes: [(Double, CatAction)] = []
    var t = start
    while t < start + seconds {
      let action = behaviour.beat(at: t, mode: mode).action
      if changes.last?.1 != action { changes.append((t, action)) }
      t += 1.0 / 30
    }
    return changes
  }

  @Test func startsAsleepAndStirsWithinSeconds() {
    var cat = CatBehaviour(clips: Self.full, seed: 7)
    let changes = run(&cat, for: 8)
    #expect(changes.first?.1 == .sleep)
    let woke = changes.first { $0.1 != .sleep }
    #expect(woke != nil)
    #expect((woke?.0 ?? 99) <= 5.1)
    #expect(woke.map { [.yawn, .stretch].contains($0.1) } == true)
  }

  @Test func awakeSpellMixesManyMovesWithoutRepeatingOneShots() {
    var cat = CatBehaviour(clips: Self.full, seed: 3)
    let changes = run(&cat, for: 40, mode: .awake)
    let distinct = Set(changes.map(\.1))
    #expect(distinct.count >= 5)
    let oneShots = changes.map(\.1).filter { ![.sit, .idle].contains($0) }
    for (a, b) in zip(oneShots, oneShots.dropFirst()) { #expect(a != b) }
    #expect(!changes.contains { $0.1 == .sleep })
  }

  @Test func cooldownsHold() {
    for seed in UInt64(1)...20 {
      var cat = CatBehaviour(clips: Self.full, seed: seed)
      let grooms = run(&cat, for: 120, mode: .awake).filter { $0.1 == .groom }.map(\.0)
      for (a, b) in zip(grooms, grooms.dropFirst()) { #expect(b - a >= 24) }
    }
  }

  @Test func napsAgainAfterAnAwakeSpell() {
    var cat = CatBehaviour(clips: Self.full, seed: 11)
    let changes = run(&cat, for: 90)
    let sleeps = changes.filter { $0.1 == .sleep }
    #expect(sleeps.count >= 2)
  }

  @Test func petCutsInWithHappyThenCarriesOn() {
    var cat = CatBehaviour(clips: Self.full, seed: 5)
    _ = run(&cat, for: 2)
    #expect(cat.beat(at: 2, mode: .free).action == .sleep)
    cat.react(.pet, at: 2.1)
    #expect(cat.beat(at: 2.1, mode: .free).action == .happy)
    #expect(cat.beat(at: 4, mode: .free).action == .happy)
    #expect(cat.beat(at: 5.5, mode: .free).action != .happy)
  }

  @Test func tapPerksAndTreatEatsThenIsPleased() {
    var cat = CatBehaviour(clips: Self.full, seed: 5)
    cat.react(.tap, at: 0)
    #expect(cat.beat(at: 0, mode: .free).action == .perk)
    cat.react(.treat, at: 1)
    #expect(cat.beat(at: 1, mode: .free).action == .eat)
    #expect(cat.beat(at: 5.1, mode: .free).action == .happy)
  }

  @Test func fixedModePassesThrough() {
    var cat = CatBehaviour(clips: Self.full)
    #expect(cat.beat(at: 0, mode: .fixed(.walk)) == CatBeat(action: .walk, lookWeight: 0.3))
    #expect(cat.beat(at: 1, mode: .fixed(.pounce)).action == .pounce)
  }

  @Test func neverCuesAClipTheModelLacks() {
    let basic = Self.full.filter { [.idle, .sit, .sleep, .walk].contains($0.key) }
    var cat = CatBehaviour(clips: basic, seed: 2)
    let changes = run(&cat, for: 120)
    #expect(changes.allSatisfy { basic[$0.1] != nil })
    cat.react(.pet, at: 121)
    #expect(basic[cat.beat(at: 121, mode: .free).action] != nil)
    cat.react(.treat, at: 122)
    #expect(basic[cat.beat(at: 122, mode: .free).action] != nil)
  }

  @Test func sameSeedSameDay() {
    var a = CatBehaviour(clips: Self.full, seed: 42)
    var b = CatBehaviour(clips: Self.full, seed: 42)
    #expect(run(&a, for: 60).map(\.1) == run(&b, for: 60).map(\.1))
  }

  @Test func headStaysStillInClipsThatMoveIt() {
    #expect(CatBehaviour.lookWeight(.sleep) == 0)
    #expect(CatBehaviour.lookWeight(.groom) == 0)
    #expect(CatBehaviour.lookWeight(.sit) == 1)
  }
}

@Suite("CatChoice")
struct CatChoiceTests {
  @Test func coatsOnlyWhereTheModelHasThem() {
    #expect(CatChoice(model: .mochi, coat: .black).coat == .natural)
    #expect(CatChoice(model: .chibi, coat: .black).coat == .black)
  }

  @Test func readsUnknownValuesAsTheStandardCat() throws {
    let json = Data(#"{"model":"dragon","coat":"plaid"}"#.utf8)
    #expect(try JSONDecoder().decode(CatChoice.self, from: json) == .standard)
    let saved = try JSONEncoder().encode(CatChoice(model: .kitten, coat: .cream))
    #expect(
      try JSONDecoder().decode(CatChoice.self, from: saved)
        == CatChoice(model: .kitten, coat: .cream))
  }
}
