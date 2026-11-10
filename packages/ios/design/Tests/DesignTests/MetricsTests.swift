import CoreGraphics
import Testing

@testable import Design

@Suite struct MetricsTests {
  @Test func spacingGrowsWithEachStep() {
    let steps = [Space.xs, Space.s, Space.m, Space.l, Space.gutter, Space.section, Space.xl]
    #expect(steps == steps.sorted())
    #expect(Set(steps).count == steps.count)
  }

  @Test func controlsMeetTheTapTarget() {
    #expect(Size.control >= 44)
    #expect(Size.button >= Size.control)
    #expect(Size.row >= Size.control)
    #expect(Size.pill < Size.control)
  }

  @Test func cornersAreConcentric() {
    let atTheGutter = Radius.sheet - Space.gutter
    let inACard = Radius.card - CardMetrics.padding
    #expect(atTheGutter == Radius.card)
    #expect(inACard == Radius.inner)
    #expect(Radius.inner > 0)
  }

  @Test func aOneLineFieldIsTheButtonCapsule() {
    let fieldHeight = Radius.control * 2
    #expect(fieldHeight == Size.button)
  }
}
