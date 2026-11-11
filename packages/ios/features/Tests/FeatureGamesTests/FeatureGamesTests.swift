import GamesInterface
import Testing
import Wire

@testable import FeatureGames

/// The same numbers every run.
private struct Seeded: RandomNumberGenerator {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

struct KibbleScaleTests {
  @Test func theBowlWeighsUntilTared() {
    var scale = KibbleScale()
    #expect(scale.reading == 0)
    scale.putBowl(onScale: true)
    #expect(scale.reading == 118)
    scale.pressTare()
    #expect(scale.reading == 0 && scale.isTared)
    scale.add(40.4)
    #expect(scale.reading == 40)
    // Off the scale, a tared bowl reads below zero.
    scale.putBowl(onScale: false)
    #expect(scale.reading == -118)
  }

  @Test func untaredTheReadingIsBowlAndFood() {
    var scale = KibbleScale()
    scale.putBowl(onScale: true)
    scale.add(41)
    #expect(scale.reading == 159)
    #expect(!scale.isTared)
  }

  @Test func kibbleGoesBackButTheBowlNeverHoldsLessThanNothing() {
    var scale = KibbleScale()
    scale.add(3)
    scale.add(-KibblePour.pinch)
    #expect(scale.food == 2.5)
    scale.add(-10)
    #expect(scale.food == 0)
  }
}

struct FeedTaskTests {
  @Test func theEmptierSheIsTheMoreSheNeeds() {
    #expect(FeedTask(full: 1).target == 25)
    #expect(FeedTask(full: 0).target == 60)
    #expect(FeedTask(full: 0.5).target == 43)
    #expect(FeedTask(target: 200).target == 60)
  }

  @Test func feedWorksOnlyWithinTolerance() {
    let small = FeedTask(target: 30)
    #expect(small.tolerance == 2)
    #expect(small.check(food: 30) == .ready(perfect: true))
    #expect(small.check(food: 31.6) == .ready(perfect: false))
    #expect(small.check(food: 33) == .tooMuch(grams: 3))
    #expect(small.check(food: 25) == .tooLittle(grams: 5))
    #expect(small.advice(food: 33) == "3 g too much: take some out")
    #expect(small.advice(food: 30) == nil)
    // 5 % of a big portion.
    let big = FeedTask(target: 60)
    #expect(big.tolerance == 3)
    #expect(big.check(food: 57) == .ready(perfect: false))
  }

  @Test func thePourModesStayInTheirRanges() {
    var rng = Seeded(state: 7)
    for _ in 0..<200 {
      #expect((8...14).contains(KibblePour.scoop(using: &rng)))
      let shake = KibblePour.shake(strength: 1, using: &rng)
      #expect((0.5...2).contains(shake))
    }
    #expect(KibblePour.flow(angle: 0.3) == 0)
    #expect(KibblePour.flow(angle: 2.5) == 20)
    #expect(KibblePour.flow(angle: 1.2) > KibblePour.flow(angle: 0.9))
    #expect(KibblePour.back(tilt: 0.5) == 0)
  }

  @Test func onlyAFastFarTipDropsAClump() {
    var rng = Seeded(state: 1)
    #expect(KibblePour.clump(turnRate: 3, angle: 1.5, sinceLast: 9, using: &rng) == nil)
    #expect(KibblePour.clump(turnRate: 6, angle: 0.9, sinceLast: 9, using: &rng) == nil)
    #expect(KibblePour.clump(turnRate: 6, angle: 1.5, sinceLast: 1, using: &rng) == nil)
    let clump = KibblePour.clump(turnRate: 6, angle: 1.5, sinceLast: 9, using: &rng)
    #expect(clump.map { (5...8).contains($0) } == true)
  }
}

struct WaterBowlTests {
  @Test func fullFlowReachesTheLineInTheFillTime() {
    var bowl = WaterBowl()
    #expect(!bowl.canServe)
    bowl.pour(flow: 1, dt: WaterBowl.fillTime)
    #expect(abs(bowl.level - WaterBowl.line) < 1e-9)
    #expect(bowl.canServe && bowl.rating == .perfect)
  }

  @Test func pastTheBrimItSpillsAndCanBeWipedUp() {
    var bowl = WaterBowl()
    bowl.pour(flow: 1, dt: 10)
    #expect(bowl.level == 1)
    #expect(bowl.isSpilling && bowl.puddle > 0.5)
    #expect(bowl.rating == .spill)
    bowl.pourOut(dt: 3)
    #expect(bowl.level < 1)
    while bowl.puddle > 0 { bowl.wipe(0.3) }
    #expect(bowl.rating == .good)
    #expect(bowl.hint != "Spilling!")
  }

  @Test func overTheLineButInTheBowlIsStillGood() {
    var bowl = WaterBowl()
    bowl.pour(flow: 1, dt: WaterBowl.fillTime * 1.2)
    #expect(bowl.isOverLine && !bowl.isSpilling)
    #expect(bowl.rating == .good)
    #expect(bowl.hint == "Past the line: tip some out")
  }
}

struct LaserPlayTests {
  private let floor = FloorArea(x: -0.4...0.4, z: -0.4...0.4)

  @Test func sheChasesAFarDotAndPouncesOnAStillNearOne() {
    var laser = LaserPlay(length: 0.2, floor: floor)
    #expect(laser.cue(cat: .zero) == nil)
    laser.aim(SIMD2(0.3, 0), dt: 1 / 60)
    #expect(laser.cue(cat: .zero) == .chase(SIMD2(0.3, 0)))
    // Close and still for long enough: a pounce.
    for _ in 0..<30 { laser.aim(SIMD2(0.05, 0), dt: 1 / 60) }
    #expect(laser.cue(cat: .zero) == .pounce(SIMD2(0.05, 0)))
  }

  @Test func theDotStaysOnTheFloor() {
    var laser = LaserPlay(length: 0.2, floor: floor)
    laser.aim(SIMD2(3, -3), dt: 0.1)
    #expect(laser.dot == SIMD2(0.4, -0.4))
  }

  @Test func chasingAndPouncingFillThePlayBar() {
    var laser = LaserPlay(length: 0.2, floor: floor)
    laser.ran(0.4)
    #expect(abs(laser.play - 0.5) < 1e-9)
    laser.pounced()
    laser.pounced()
    laser.pounced()
    #expect(laser.isDone && laser.play == 1)
    laser.aim(SIMD2(0.3, 0), dt: 0.1)
    #expect(laser.cue(cat: .zero) == nil)
  }
}

struct BrushStrokesTests {
  @Test func withTheGrainFillsGroomAndSheds() {
    var brush = BrushStrokes(length: 0.2)
    #expect(brush.stroke(distance: 0.01, fit: 0.9) == .enjoys(purrs: true))
    #expect(brush.stroke(distance: 0.01, fit: 0.9) == .enjoys(purrs: false))
    #expect(brush.tufts == 3)
    #expect(brush.isPurring)
    for _ in 0..<80 { _ = brush.stroke(distance: 0.01, fit: 1) }
    #expect(brush.isDone)
  }

  @Test func againstTheGrainSheFlinchesAndCoolsOff() {
    var brush = BrushStrokes(length: 0.2)
    _ = brush.stroke(distance: 0.05, fit: 1)
    #expect(brush.content > 0.4)
    #expect(brush.stroke(distance: 0.03, fit: -0.9) == nil)
    #expect(brush.stroke(distance: 0.03, fit: -0.9) == .flinches)
    #expect(brush.content < 0.1)
    #expect(brush.groom < 0.1)
  }

  @Test func contentmentFadesWithoutStrokes() {
    var brush = BrushStrokes(length: 0.2)
    _ = brush.stroke(distance: 0.05, fit: 1)
    let before = brush.content
    brush.update(dt: 2)
    #expect(!brush.isPurring)
    #expect(brush.content < before)
  }
}

struct GameResultTests {
  @Test func aFeedFillsFullWithItsGramsAndPaysAsAGame() {
    let result = GameResult.feed(target: 40, food: 41.2)
    #expect(result.score == 90)
    #expect(result.events == [.fed(grams: 41), .gamePlayed(game: "feed", score: 90, won: true)])
  }

  @Test func theOverfeedTableTakesMoreTheFurtherPastTheZone() {
    // Target 40: zone 38...42, room 10, hard cap 52.
    #expect(FeedPenalty.hardCap(target: 40) == 52)
    #expect(FeedPenalty.over(target: 40, food: 42) == nil)
    #expect(FeedPenalty.over(target: 40, food: 10) == nil)
    #expect(FeedPenalty.over(target: 40, food: 43) == FeedPenalty(score: 30, tier: 0))
    #expect(FeedPenalty.over(target: 40, food: 47) == FeedPenalty(score: 30, tier: 0))
    #expect(FeedPenalty.over(target: 40, food: 48) == FeedPenalty(score: 0, tier: 1))
    #expect(FeedPenalty.over(target: 40, food: 52) == FeedPenalty(score: 0, tier: 1))
    let scores = FeedPenalty.tiers.map(\.score)
    #expect(scores == scores.sorted(by: >))
    #expect(FeedPenalty.tiers.map(\.upTo) == [0.5, 1])
  }

  @Test func theOverfeedTableRejectsWhatIsNotAWeight() {
    #expect(FeedPenalty.over(target: 40, food: -5) == nil)
    #expect(FeedPenalty.over(target: 40, food: .nan) == nil)
    #expect(FeedPenalty.over(target: 40, food: .infinity) == nil)
    // Past the cap counts as the cap; a portion off the range is moved onto it.
    #expect(FeedPenalty.over(target: 40, food: 900) == FeedPenalty(score: 0, tier: 1))
    #expect(FeedPenalty.over(target: 5, food: 29) == FeedPenalty(score: 30, tier: 0))
    #expect(FeedPenalty.hardCap(target: 5) == FeedPenalty.hardCap(target: 25))
    #expect(FeedTask(target: 40).hardCap == 52)
  }

  @Test func anOverfedBowlPaysLittleAndSaysSo() {
    let mild = GameResult.feed(target: 40, food: 45)
    #expect(mild.tooMuch)
    #expect(mild.score == 30)
    #expect(mild.line == "Too much! She's stuffed")
    #expect(mild.events == [.fed(grams: 45), .gamePlayed(game: "feed", score: 30, won: true)])
    #expect(GameResult.feed(target: 40, food: 51).score == 0)
    let fine = GameResult.feed(target: 40, food: 42)
    #expect(!fine.tooMuch)
    #expect(fine.score == 80)
    // Under the zone it is no overfeed, only a smaller reward.
    #expect(!GameResult.feed(target: 40, food: 30).tooMuch)
    #expect(!GameResult.feed(target: 40, food: -3).tooMuch)
  }

  @Test func aPuddleIsAMildTooMuchForWater() {
    var bowl = WaterBowl()
    bowl.pour(flow: 1, dt: WaterBowl.fillTime)
    #expect(!GameResult.water(bowl).tooMuch)
    bowl.pour(flow: 1, dt: 10)
    #expect(GameResult.water(bowl).tooMuch)
    #expect(GameResult.water(bowl).line.hasPrefix("Too much!"))
  }

  @Test func eachGameGoesToTheJournalItsOwnWay() {
    #expect(
      GameResult(game: .brush, score: 100).events == [
        .petted, .gamePlayed(game: "brush", score: 100, won: true),
      ])
    #expect(
      GameResult(game: .laser, score: 100).events == [
        .gamePlayed(game: "laser", score: 100, won: true)
      ])
    #expect(
      GameResult(game: .water, score: 70).events == [
        .gamePlayed(game: "water", score: 70, won: true)
      ])
    #expect(GameResult(game: .laser, score: 400).score == 100)
  }

  @Test func waterScoresTheLineAndThePuddle() {
    var bowl = WaterBowl()
    bowl.pour(flow: 1, dt: WaterBowl.fillTime)
    #expect(GameResult.water(bowl).score == 100)
    bowl.pour(flow: 1, dt: 10)
    #expect(GameResult.water(bowl).score < 50)
  }
}
