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
  }

  @Test func radiiGrowFromTagToHero() {
    #expect(
      Radius.tag < Radius.control && Radius.control < Radius.card && Radius.card < Radius.hero)
  }
}
