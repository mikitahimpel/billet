import Testing

@testable import RoomInterface

@Suite struct RoomQualityTests {
  private let nominal = RoomConditions(heat: .nominal, lowPower: false)

  @Test func conditionsAskForTheTierTheirHeatNames() {
    #expect(nominal.wanted == .full)
    #expect(RoomConditions(heat: .nominal, lowPower: true).wanted == .fair)
    #expect(RoomConditions(heat: .fair, lowPower: false).wanted == .fair)
    #expect(RoomConditions(heat: .serious, lowPower: true).wanted == .serious)
    #expect(RoomConditions(heat: .critical, lowPower: false).wanted == .critical)
  }

  @Test func degradesAtOnceAndSkipsSteps() {
    var policy = RoomQualityPolicy()
    #expect(policy.update(RoomConditions(heat: .serious, lowPower: false), at: 0) == .serious)
    #expect(policy.update(RoomConditions(heat: .critical, lowPower: false), at: 1) == .critical)
  }

  @Test func recoversOneStepAfterTheWaitNotBefore() {
    var policy = RoomQualityPolicy(tier: .serious)
    #expect(policy.update(nominal, at: 100) == .serious)
    #expect(policy.update(nominal, at: 100 + RoomQualityPolicy.recoverAfter - 1) == .serious)
    #expect(policy.update(nominal, at: 100 + RoomQualityPolicy.recoverAfter) == .fair)
    #expect(policy.update(nominal, at: 100 + RoomQualityPolicy.recoverAfter + 1) == .fair)
    #expect(policy.update(nominal, at: 100 + 2 * RoomQualityPolicy.recoverAfter) == .full)
  }

  @Test func aRelapseRestartsTheWait() {
    var policy = RoomQualityPolicy(tier: .fair)
    policy.update(nominal, at: 0)
    policy.update(RoomConditions(heat: .fair, lowPower: false), at: 60)
    #expect(policy.update(nominal, at: 100) == .fair)
    #expect(policy.update(nominal, at: 100 + RoomQualityPolicy.recoverAfter) == .full)
  }

  @Test func plansOnlyRemoveWorkAsTheTierRises() {
    let plans = RoomQualityTier.allCases.map(\.plan)
    for (a, b) in zip(plans, plans.dropFirst()) {
      #expect(!(b.motes && !a.motes))
      #expect(!(b.antialiasing && !a.antialiasing))
      #expect(!(b.sway && !a.sway))
      #expect(b.splatDetail >= a.splatDetail)
      #expect(!(a.still && !b.still))
    }
    #expect(RoomQualityTier.full.plan.splatRate == 0)
    #expect(RoomQualityTier.critical.plan.still)
  }
}

@Suite struct SplatPruningTests {
  @Test func keepsTheMostImportantInFileOrder() {
    let importance: [Float] = [0.1, 0.9, 0.5, 0.7, 0.2]
    #expect(SplatPruning.survivors(importance: importance, keeping: 0.4) == [1, 3])
    #expect(SplatPruning.survivors(importance: importance, keeping: 1) == [0, 1, 2, 3, 4])
  }

  @Test func tiesGoToTheLowerIndex() {
    #expect(SplatPruning.survivors(importance: [1, 1, 1, 1], keeping: 0.5) == [0, 1])
  }

  @Test func opacityAndAreaBothRaiseImportance() {
    let small = SplatPruning.importance(logitOpacity: 0, logScales: [-5, -5, -5])
    let big = SplatPruning.importance(logitOpacity: 0, logScales: [-4, -4, -4])
    let faint = SplatPruning.importance(logitOpacity: -4, logScales: [-4, -4, -4])
    #expect(big > small)
    #expect(big > faint)
  }

  @Test func detailLevelsLandInTheTargetRange() {
    let counts = SplatDetail.allCases.map { Int(131_000 * $0.keep) }
    #expect(counts[0] == 131_000)
    #expect((50_000...75_000).contains(counts[1]))
    #expect((50_000...75_000).contains(counts[2]))
  }

  @Test func boostGrowsAsMoreIsCut() {
    #expect(SplatPruning.logScaleBoost(keeping: 1) == 0)
    #expect(SplatPruning.logScaleBoost(keeping: 0.4) > SplatPruning.logScaleBoost(keeping: 0.55))
  }
}
