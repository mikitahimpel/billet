import Testing

@testable import FeatureGames

@Suite struct GameFramingTests {
  @Test func distanceFollowsTheNarrowerSide() {
    let tall = GameFraming.distance(radius: 0.5, tanHalf: 0.2, aspect: 0.5, fill: 0.9, push: 0)
    let wide = GameFraming.distance(radius: 0.5, tanHalf: 0.2, aspect: 2, fill: 0.9, push: 0)
    #expect(abs(tall - 0.5 / (0.1 * 0.9)) < 0.0001)
    #expect(abs(wide - 0.5 / (0.2 * 0.9)) < 0.0001)
  }

  @Test func pushComesCloserAndATinyRadiusStillStandsBack() {
    let flat = GameFraming.distance(radius: 0.5, tanHalf: 0.2, aspect: 0.5, fill: 0.9, push: 0)
    let pushed = GameFraming.distance(radius: 0.5, tanHalf: 0.2, aspect: 0.5, fill: 0.9, push: 1)
    #expect(abs(pushed - flat * 0.9) < 0.0001)
    #expect(GameFraming.distance(radius: 0, tanHalf: 0.2, aspect: 0.5, fill: 0.9, push: 0) > 0)
  }

  @Test func smoothingIsTheSameHoweverTheTimeIsCut() {
    var coarse: Float = 0
    coarse = GameFraming.smooth(coarse, toward: 1, dt: 0.1, rate: 5)
    var fine: Float = 0
    for _ in 0..<10 { fine = GameFraming.smooth(fine, toward: 1, dt: 0.01, rate: 5) }
    #expect(abs(coarse - fine) < 0.0001)
  }

  @Test func smoothingStaysPutWithoutTimeAndLandsOnItsTarget() {
    #expect(GameFraming.smooth(3, toward: 9, dt: 0, rate: 5) == 3)
    var value: Float = 0
    for _ in 0..<600 { value = GameFraming.smooth(value, toward: 1, dt: 1 / 60, rate: 5) }
    #expect(value == 1)
  }
}
