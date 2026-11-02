import Foundation
import PetScene
import RealityKit
import Testing

@testable import PetSceneReality

struct OnboardingTimelineTests {
  private let flight = OnboardingTimeline(reduceMotion: false)
  private let calm = OnboardingTimeline(reduceMotion: true)

  @Test func theFlightStartsDarkAndFarAndEndsLitAtItsPlace() {
    #expect(flight.away(0) == 1)
    #expect(flight.darkness(0) == 1)
    #expect(flight.away(flight.duration) == 0)
    #expect(flight.darkness(flight.duration) == 0)
    #expect(flight.warmth(flight.duration) == 1)
    #expect(flight.heartGlow(flight.duration) == 1)
    for index in OnboardingLayout.candles.indices {
      #expect(flight.candle(index, 0) == 0)
      #expect(flight.candle(index, flight.duration) == 1)
    }
  }

  @Test func itTakesFourToSixSeconds() {
    #expect((4...6).contains(flight.duration))
  }

  @Test func theCameraNeverBacksAwayAndTheDarkNeverReturns() {
    var lastAway: Float = 2
    var lastDark = 2.0
    for step in 0...104 {
      let time = Double(step) * 0.05
      #expect(flight.away(time) <= lastAway)
      #expect(flight.darkness(time) <= lastDark)
      lastAway = flight.away(time)
      lastDark = flight.darkness(time)
    }
  }

  @Test func theCandlesCatchOneByOneThenTheLightsRunAlongTheWindow() {
    let caught = OnboardingLayout.candles.indices.map { index in
      (0...200).first { flight.candle(index, Double($0) * 0.025) > 0.5 } ?? .max
    }
    #expect(caught == caught.sorted())
    #expect(Set(caught).count == caught.count)
    let count = OnboardingLayout.beads.count
    let firstBead = (0...200).first { flight.bead(0, of: count, Double($0) * 0.025) > 0.5 } ?? 0
    let lastBead =
      (0...200).first { flight.bead(count - 1, of: count, Double($0) * 0.025) > 0.5 } ?? 0
    #expect(firstBead > caught.last ?? 0)
    #expect(lastBead > firstBead)
  }

  @Test func withMotionReducedNothingFliesAndAllFadesUpTogether() {
    for step in 0...40 {
      let time = Double(step) * 0.05
      #expect(calm.away(time) == 0)
      #expect(calm.candle(0, time) == calm.candle(3, time))
      #expect(calm.bead(0, of: 15, time) == calm.bead(14, of: 15, time))
    }
    #expect(calm.duration < flight.duration)
    #expect(calm.darkness(calm.duration) == 0)
  }

  @Test func theHeartBeatsInPairsAndRestsBetween() {
    let samples = (0..<130).map { HeartMotion.beat(Double($0) * 0.01) }
    let peaks = samples.indices.dropFirst().dropLast().filter {
      samples[$0] > samples[$0 - 1] && samples[$0] >= samples[$0 + 1] && samples[$0] > 0.3
    }
    #expect(peaks.count == 2)
    #expect(HeartMotion.beat(1.0) < 0.05)
    #expect(HeartMotion.beat(0.12) == HeartMotion.beat(0.12 + HeartMotion.period))
  }

  @Test func aSquishSettlesBack() {
    #expect(HeartMotion.squish(0) == .one)
    #expect(HeartMotion.squish(0.09) != .one)
    #expect(HeartMotion.squish(1) == .one)
    #expect(HeartMotion.squish(-0.1) == .one)
  }
}

@MainActor
struct OnboardingHeartTests {
  @Test func theHeartLoadsAsTwoHalvesSideBySide() async throws {
    let heart = try #require(await OnboardingStage.heartModel())
    let left = try #require(heart.findEntity(named: "heart_L"))
    let right = try #require(heart.findEntity(named: "heart_R"))
    let leftBounds = left.visualBounds(relativeTo: heart)
    let rightBounds = right.visualBounds(relativeTo: heart)
    #expect(!leftBounds.isEmpty && !rightBounds.isEmpty)
    #expect(leftBounds.center.x < 0 && rightBounds.center.x > 0)
    // Mirror images: as tall as each other, and as far out.
    #expect(abs(leftBounds.extents.y - rightBounds.extents.y) < 0.002)
    #expect(abs(leftBounds.center.x + rightBounds.center.x) < 0.002)
  }

  @Test func theHeartFileStaysSmall() throws {
    let url = try #require(Bundle.module.url(forResource: "Heart", withExtension: "reality"))
    let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    #expect(size < 300_000)
  }
}

struct HeartHalvesTests {
  private func run(
    _ halves: inout HeartHalves, _ moment: OnboardingSceneState.Moment, mine: HeartSide = .left,
    seconds: Double, reduceMotion: Bool = false
  ) -> Int {
    var meetings = 0
    for _ in 0..<Int(seconds * 60) {
      if halves.step(1.0 / 60, towards: moment, mine: mine, reduceMotion: reduceMotion) {
        meetings += 1
      }
    }
    return meetings
  }

  @Test func apartMineStaysOnItsSideAndThePartnersWaitsFaintOnTheOther() {
    var halves = HeartHalves()
    _ = run(&halves, .apart(partner: .waiting), seconds: 4)
    #expect(halves.me.offset.x < -0.5)
    #expect(halves.partner.offset.x > 0.5)
    #expect(halves.me.opacity > 0.95)
    #expect(halves.partner.opacity > 0.2 && halves.partner.opacity < 0.6)
  }

  @Test func theMirrorPutsMineOnTheRight() {
    var halves = HeartHalves(mine: .right)
    _ = run(&halves, .apart(partner: .waiting), mine: .right, seconds: 4)
    #expect(halves.me.offset.x > 0.5)
    #expect(halves.partner.offset.x < -0.5)
  }

  @Test func theAwayHalfFliesInAndTheyMeetOnce() {
    var halves = HeartHalves()
    _ = run(&halves, .apart(partner: .away), seconds: 4)
    #expect(halves.partner.opacity < 0.05)
    #expect(simd_length(halves.partner.offset) > 5)
    let meetings = run(&halves, .together, seconds: 6)
    #expect(meetings == 1)
    #expect(halves.partner.opacity > 0.95)
  }

  @Test func neverApartNeverBursts() {
    var halves = HeartHalves()
    #expect(run(&halves, .together, seconds: 2) == 0)
    #expect(run(&halves, .resting, seconds: 2) == 0)
  }

  @Test func withMotionReducedNothingTravelsAndTheyStillMeet() {
    var halves = HeartHalves()
    _ = halves.step(1.0 / 60, towards: .apart(partner: .away), mine: .left, reduceMotion: true)
    #expect(
      halves.partner.offset
        == HeartHalves.targets(.apart(partner: .away), mine: .left).partner.offset)
    _ = run(&halves, .apart(partner: .away), seconds: 2, reduceMotion: true)
    _ = halves.step(1.0 / 60, towards: .together, mine: .left, reduceMotion: true)
    #expect(halves.partner.offset == .zero)
    #expect(run(&halves, .together, seconds: 3, reduceMotion: true) == 1)
  }

  @Test func burstFlashesThenFades() {
    #expect(OnboardingBurst.strength(0) == 0)
    #expect(OnboardingBurst.strength(0.12) > 0.95)
    #expect(OnboardingBurst.strength(OnboardingBurst.length) == 0)
    #expect(OnboardingBurst.spread(1) > OnboardingBurst.spread(0.1))
  }
}
