import Testing

@testable import DesignSystem

@Suite struct RadiusTests {
  @Test func theScaleIsCardPlatePaper() {
    #expect(Radius.card == 24)
    #expect(Radius.plate == 16)
    #expect(Radius.paper == 10)
  }

  @Test func nestingFollowsTheOuterCorner() {
    #expect(Radius.nested(in: 40, padding: 8) == 32)
  }

  @Test func nestingNeverGoesBelowThePlate() {
    #expect(Radius.nested(in: Radius.card, padding: Spacing.medium) == Radius.plate)
    #expect(Radius.nested(in: Radius.plate, padding: 8) == Radius.plate)
  }
}
