import Pet
import Testing

@Suite("CatNoticing")
struct CatNoticingTests {
  private let places = [
    CatStimulus(.viewer, .seen, bearing: 0.4, elevation: 0.2, salience: 0.6, hold: 2.5),
    CatStimulus(.place("sill"), .seen, bearing: -0.5, elevation: 0.25, salience: 0.5, hold: 4),
    CatStimulus(.place("ball"), .seen, bearing: 0.1, elevation: -0.2, salience: 0.3, hold: 2),
  ]

  /// A minute of her sitting alone, at 60 frames a second.
  private func minute(seed: UInt64, _ context: CatNoticing.Context = .init()) -> [CatRegard] {
    var cat = CatNoticing(seed: seed)
    cat.places = places
    return (0..<3600).map { cat.advance(to: Double($0) / 60, context) }
  }

  @Test func theSameSeedIsTheSameCat() {
    #expect(minute(seed: 7) == minute(seed: 7))
    #expect(minute(seed: 7) != minute(seed: 8))
  }

  @Test func leftAloneSheLooksAtTheThingsAroundHer() {
    let seen = Set(minute(seed: 3).compactMap(\.source))
    #expect(seen.contains(.viewer))
    #expect(seen.contains(.place("sill")))
    #expect(seen.contains(.sound))
  }

  @Test func sheIsStillMostOfTheTimeAndNeverForLong() {
    for seed in [1, 2, 3, 4, 5] as [UInt64] {
      let run = minute(seed: seed)
      var turns = 0
      var longest = 0
      var quiet = 0
      for (before, after) in zip(run, run.dropFirst()) {
        if abs(after.headYaw - before.headYaw) > 0.05 {
          turns += 1
          quiet = 0
        } else {
          quiet += 1
          longest = max(longest, quiet)
        }
      }
      #expect(turns >= 6, "seed \(seed) turned her head \(turns) times in a minute")
      #expect(turns <= 40, "seed \(seed) turned her head \(turns) times in a minute")
      #expect(longest < 20 * 60, "seed \(seed) held her head \(longest / 60) s")
    }
  }

  @Test func theHeadStaysWithinTheNeck() {
    for regard in minute(seed: 11) {
      #expect(abs(regard.headYaw) <= CatNoticing.neck.resting)
      #expect(regard.headPitch >= CatNoticing.neck.down && regard.headPitch <= CatNoticing.neck.up)
    }
    for regard in minute(seed: 11, .init(moving: true)) {
      #expect(abs(regard.headYaw) <= CatNoticing.neck.moving)
    }
  }

  @Test func anEarGoesToASoundBeforeTheHeadAndSheFreezes() {
    var cat = CatNoticing(seed: 1)
    _ = cat.advance(to: 0.5)
    cat.notice(CatStimulus(.partner, .heard, bearing: -1.2, salience: 0.9, hold: 2), now: 0.5)
    let first = cat.advance(to: 0.5 + 1.0 / 60)
    #expect(first.earLeft > 0.3)
    #expect(first.earLeft > first.earRight)
    #expect(first.headYaw == 0)
    #expect(first.stillness > 0.8)
    let later = cat.advance(to: 1)
    #expect(later.headYaw == -CatNoticing.neck.resting)
    #expect(later.source == .partner)
    #expect(later.stillness > 0.8)
  }

  @Test func sheGetsUsedToWhatRepeats() {
    var cat = CatNoticing(seed: 1)
    let camera = CatStimulus(.viewer, .seen, bearing: 0.3, salience: 0.6, hold: 1)
    var felt: [Double] = []
    for turn in 0..<4 {
      let now = Double(turn) * 5
      _ = cat.advance(to: now)
      felt.append(cat.felt(camera))
      cat.notice(camera, now: now)
    }
    #expect(felt[0] > CatAttention.headThreshold)
    #expect(felt[3] < CatAttention.headThreshold)
    #expect(felt == felt.sorted(by: >))
    _ = cat.advance(to: 600)
    #expect(cat.felt(camera) > 0.95 * felt[0])
  }

  @Test func noticingWakesHerAndSheCalmsAgain() {
    var cat = CatNoticing(seed: 1)
    _ = cat.advance(to: 1)
    let calm = cat.arousal
    cat.notice(CatStimulus(.touch, .seen, bearing: 0, salience: 0.9, hold: 1), now: 1)
    let woken = cat.arousal
    #expect(woken > calm + 0.3)
    for second in 2..<120 { _ = cat.advance(to: Double(second)) }
    #expect(cat.arousal < woken - 0.2)
  }

  @Test func drowsySheNoticesLessAndLooksAboutLess() {
    var cat = CatNoticing(seed: 1)
    let sound = CatStimulus(.sound, .heard, bearing: 1, salience: 0.6, hold: 1)
    _ = cat.advance(to: 0, .init(drowse: 0))
    let awake = cat.felt(sound)
    _ = cat.advance(to: 0, .init(drowse: 0.7))
    #expect(cat.felt(sound) < 0.7 * awake)
    func looks(_ drowse: Double) -> Int {
      let run = minute(seed: 5, .init(drowse: drowse))
      return zip(run, run.dropFirst()).filter { $1.source != nil && $0.source != $1.source }.count
    }
    #expect(looks(0.7) < looks(0))
  }

  @Test func sheDoesNotLookAtTheSameThingTimeAfterTime() {
    let run = minute(seed: 9)
    var sources: [CatStimulus.Source] = []
    for (before, after) in zip(run, run.dropFirst()) where after.source != before.source {
      if let source = after.source, source != .sound { sources.append(source) }
    }
    var streak = 1
    var longest = 1
    for (a, b) in zip(sources, sources.dropFirst()) {
      streak = a == b ? streak + 1 : 1
      longest = max(longest, streak)
    }
    #expect(sources.count >= 5)
    #expect(longest <= 3)
  }

  @Test func arrivingSheLooksAboutAtOnceWhateverSheWasGlancingAt() {
    var cat = CatNoticing(seed: 4)
    cat.places = places
    _ = cat.advance(to: 0.1, .init(moving: true))
    cat.notice(CatStimulus(.destination, .own, bearing: 0.1, salience: 0.8, hold: 5), now: 0.1)
    _ = cat.advance(to: 0.2, .init(moving: true))
    let seconds = cat.survey(now: 0.2)
    #expect(seconds >= 0.9 && seconds <= 2.1)
    let source = cat.advance(to: 0.22).source
    #expect(source != nil && source != .destination)
  }

  @Test func herOwnNoisesNeverTakeHerOffSomething() {
    var cat = CatNoticing(seed: 6)
    _ = cat.advance(to: 0)
    cat.notice(CatStimulus(.noise, .heard, bearing: -2, salience: 1, hold: 30), now: 0)
    for frame in 1..<(25 * 60) {
      let regard = cat.advance(to: Double(frame) / 60)
      if frame > 60 { #expect(regard.source == .noise) }
    }
  }

  @Test func sheBlinksLettingGo() {
    var cat = CatNoticing(seed: 2)
    _ = cat.advance(to: 0)
    cat.notice(CatStimulus(.viewer, .seen, bearing: 0.2, salience: 0.8, hold: 1), now: 0)
    var blinks: [Double] = []
    for frame in 1...90 where cat.advance(to: Double(frame) / 60).blink {
      blinks.append(Double(frame) / 60)
    }
    #expect(blinks.count == 1)
    #expect(abs((blinks.first ?? 0) - 1) < 0.05)
  }
}
