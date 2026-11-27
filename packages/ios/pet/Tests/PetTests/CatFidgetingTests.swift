import Testing

@testable import Pet

@Suite struct CatFidgetingTests {
  private func play(
    seed: UInt64, seconds: Double = 600, _ mood: CatFidgeting.Mood = .init()
  ) -> [(at: Double, fidget: CatFidget)] {
    var fidgeting = CatFidgeting(seed: seed)
    var out: [(Double, CatFidget)] = []
    var now = 0.0
    while now < seconds {
      if let fidget = fidgeting.advance(to: now, mood) { out.append((now, fidget)) }
      now += 0.1
    }
    return out
  }

  @Test func theSameSeedFidgetsTheSame() {
    let one = play(seed: 3)
    let two = play(seed: 3)
    #expect(one.map(\.fidget) == two.map(\.fidget))
    #expect(one.map(\.at) == two.map(\.at))
    #expect(one.map(\.fidget) != play(seed: 4).map(\.fidget))
  }

  @Test func sheNeverDoesTheSameThingSoonerThanItsRest() {
    let played = play(seed: 11)
    var last: [CatFidget: Double] = [:]
    for (at, fidget) in played {
      if let before = last[fidget] { #expect(at - before >= fidget.rest) }
      last[fidget] = at
    }
    #expect(Set(played.map(\.fidget)).count >= 6)
  }

  @Test func heldStillSheDoesNothing() {
    #expect(play(seed: 5, .init(stillness: 0.9)).isEmpty)
    #expect(CatFidgeting.weights(.init(stillness: 0.9)).isEmpty)
  }

  @Test func lettingGoBringsTheNextOneForward() {
    var fidgeting = CatFidgeting(seed: 9)
    var now = 0.0
    while now < 100 {
      _ = fidgeting.advance(to: now, .init(stillness: 1))
      now += 0.1
    }
    var first: Double?
    while now < 110, first == nil {
      if fidgeting.advance(to: now, .init()) != nil { first = now }
      now += 0.1
    }
    #expect(first.map { $0 - 100 <= 1.4 } == true)
  }

  @Test func sleepySheYawnsMoreAndFidgetsLess() {
    let awake = play(seed: 21, .init(arousal: 0.6))
    let sleepy = play(seed: 21, .init(arousal: 0.1, drowse: 0.7))
    #expect(sleepy.count < awake.count)
    #expect(sleepy.filter { $0.fidget == .yawn }.count > awake.filter { $0.fidget == .yawn }.count)
  }

  @Test func settlingSheSighsFirst() {
    var sighs = 0
    for seed in UInt64(1)...40 {
      var fidgeting = CatFidgeting(seed: seed)
      var now = 0.0
      var first: CatFidget?
      while now < 3, first == nil {
        first = fidgeting.advance(to: now, .init(settling: true))
        now += 0.1
      }
      if first == .sigh { sighs += 1 }
    }
    #expect(sighs >= 14)
  }

  @Test func directedSheLeavesTheLargeActsToWhoeverDirects() {
    let played = play(seed: 2, seconds: 1200, .init(directed: true))
    #expect(!played.isEmpty)
    #expect(played.allSatisfy { !$0.fidget.large })
  }
}
