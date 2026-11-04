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
      case .twitch: clips[action] = CatClipInfo(duration: 2.5, loops: false, base: .sleep)
      case .rollOver: clips[action] = CatClipInfo(duration: 4, loops: false, base: .sit)
      case .bat: clips[action] = CatClipInfo(duration: 1.4, loops: false, base: .sit)
      case .headbutt: clips[action] = CatClipInfo(duration: 1.8, loops: false, base: .stand)
      case .reachUp: clips[action] = CatClipInfo(duration: 2.2, loops: false, base: .stand)
      case .grab, .sniff, .wave, .dangle, .loaf, .run, .lieDown, .groomFlank, .groomTail,
        .lickLips, .startle, .headTilt, .carry, .rubSide, .lookUp, .jumpUp, .jumpDown:
        continue
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

  @Test func aSleepyLifeKeepsItAsleepInFreeMode() {
    var cat = CatBehaviour(clips: Self.full, seed: 7)
    cat.follow(LifeDrive(asleep: true, focus: .rested))
    let changes = run(&cat, for: 120)
    let awake = changes.filter { ![.sleep, .twitch].contains($0.1) }
    #expect(awake.isEmpty)
    // A touch still wakes it.
    cat.react(.pet, at: 120)
    #expect(cat.beat(at: 120, mode: .free).action == .happy)
  }

  @Test func aPlayfulLifeCrouchesToPounceAndAContentOneNever() {
    var playful = CatBehaviour(clips: Self.full, seed: 3)
    playful.follow(LifeDrive(focus: .playful))
    var content = CatBehaviour(clips: Self.full, seed: 3)
    let wanting = run(&playful, for: 600, mode: .awake).filter { $0.1 == .crouchWiggle }
    let calm = run(&content, for: 600, mode: .awake).filter { $0.1 == .crouchWiggle }
    #expect(!wanting.isEmpty)
    #expect(calm.isEmpty)
  }

  @Test func aWakeCueStretchesThenLooksAtTheViewerAndStaysUp() {
    var cat = CatBehaviour(clips: Self.full, seed: 7)
    cat.cue(.wakeUp, at: 0)
    _ = cat.beat(at: 0, mode: .free)
    cat.cue(.lookAtCamera, at: 0.8)
    let changes = run(&cat, from: 0, for: 6)
    #expect(changes.first?.1 == .stretch)
    // The look waits for the stretch, then rests where the head may turn.
    let look = changes.first { $0.0 > 0 && $0.1 != .stretch }
    #expect(look?.1 == .sit)
    #expect(abs((look?.0 ?? 0) - 1.5) < 0.05)
    #expect(CatBehaviour.lookWeight(.sit) == 1)
    #expect(!run(&cat, from: 6, for: 15).contains { $0.1 == .sleep })
  }

  @Test func aWakeCueFallsBackForModelsWithoutAStretch() {
    var clips = Self.full
    clips[.stretch] = nil
    clips[.yawn] = nil
    var cat = CatBehaviour(clips: clips, seed: 2)
    cat.cue(.wakeUp, at: 0)
    #expect(cat.beat(at: 0, mode: .free).action == .perk)
  }

  @Test func aLookCueOnItsOwnCutsInAtOnce() {
    var cat = CatBehaviour(clips: Self.full, seed: 4)
    _ = run(&cat, for: 1)
    cat.cue(.lookAtCamera, at: 1)
    #expect(cat.beat(at: 1, mode: .free).action == .sit)
    #expect(cat.beat(at: 1 + CatBehaviour.viewerLook - 0.1, mode: .free).action == .sit)
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

  /// A smaller set, with no twitch, yawn or groom.
  private static let fewer = full.filter {
    [.idle, .walk, .sit, .sleep, .crouchWiggle, .pounce, .eat, .blink, .look, .tailFlick, .happy]
      .contains($0.key)
  }

  /// Clips the room plays on its own; the rest are the small actions people notice.
  private static let plain: Set<CatAction> = [.idle, .sit, .sleep, .walk]

  /// The fewest different small actions seen in any 20 s on Home over ten minutes.
  private func fewestSmallActions(_ clips: [CatAction: CatClipInfo], seed: UInt64) -> Int {
    var cat = CatBehaviour(clips: clips, seed: seed)
    let step = 1.0 / 10
    var playing: [(Double, CatAction)] = []
    var t = 0.0
    while t < 600 {
      playing.append((t, cat.beat(at: t, mode: .free).action))
      t += step
    }
    let window = Int(20 / step)
    var fewest = Int.max
    for start in stride(from: 0, through: playing.count - window, by: 10) {
      let seen = Set(playing[start..<start + window].map(\.1).filter { !Self.plain.contains($0) })
      fewest = min(fewest, seen.count)
    }
    return fewest
  }

  @Test func anyTwentySecondsShowsTwoSmallActions() {
    for seed in UInt64(1)...12 {
      #expect(fewestSmallActions(Self.full, seed: seed) >= 2, "seed \(seed)")
      #expect(fewestSmallActions(Self.fewer, seed: seed) >= 2, "fewer clips, seed \(seed)")
    }
  }

  @Test func napsTwitch() {
    var cat = CatBehaviour(clips: Self.full, seed: 4)
    let changes = run(&cat, for: 120)
    #expect(changes.contains { $0.1 == .twitch })
  }

  @Test func aHeldLookTurnsTheHeadInAnyClipButSleep() {
    let groom = CatBeat(action: .groom, lookWeight: 0)
    #expect(CatBehaviour.lookWeight(for: groom, holding: true, reduceMotion: false) == 0.85)
    #expect(CatBehaviour.lookWeight(for: groom, holding: false, reduceMotion: false) == 0)
    let sleep = CatBeat(action: .sleep, lookWeight: 0)
    #expect(CatBehaviour.lookWeight(for: sleep, holding: true, reduceMotion: false) == 0)
    let sit = CatBeat(action: .sit, lookWeight: 1)
    #expect(CatBehaviour.lookWeight(for: sit, holding: true, reduceMotion: true) == 0)
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
    #expect(CatChoice(model: .idolGinger, coat: .black).coat == .natural)
    #expect(CatChoice(model: .detailed, coat: .black).coat == .black)
  }

  @Test func theDetailedGingerCatIsTheStandard() {
    #expect(CatChoice.standard == CatChoice(model: .detailed, coat: .natural))
  }

  @Test(arguments: ["mochi", "slim", "blocky", "tabby", "plush", "chibi", "kitten", "tuxedo"])
  func aSavedRemovedCatReadsAsTheStandard(model: String) throws {
    let json = Data(#"{"model":"\#(model)","coat":"natural"}"#.utf8)
    #expect(try JSONDecoder().decode(CatChoice.self, from: json) == .standard)
  }

  @Test func readsUnknownValuesAsTheStandardCat() throws {
    let json = Data(#"{"model":"dragon","coat":"plaid"}"#.utf8)
    #expect(try JSONDecoder().decode(CatChoice.self, from: json) == .standard)
    let saved = try JSONEncoder().encode(CatChoice(model: .detailedKitten, coat: .black))
    #expect(
      try JSONDecoder().decode(CatChoice.self, from: saved)
        == CatChoice(model: .detailedKitten, coat: .black))
  }

  /// The palette-painted cats are gone and with them the coats only they wore.
  @Test(arguments: ["ginger", "cream"])
  func aSavedRemovedCoatReadsAsTheOneTheCatWasMadeWith(coat: String) throws {
    let json = Data(#"{"model":"tuxedo","coat":"\#(coat)"}"#.utf8)
    #expect(try JSONDecoder().decode(CatChoice.self, from: json) == .standard)
    let detailed = Data(#"{"model":"detailed","coat":"\#(coat)"}"#.utf8)
    #expect(try JSONDecoder().decode(CatChoice.self, from: detailed).coat == .natural)
  }
}
