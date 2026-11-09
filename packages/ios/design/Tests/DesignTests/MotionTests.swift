import Testing

@testable import Design

@Suite struct MotionTests {
  @Test func quickIsShorterThanStandard() {
    #expect(0 < Motion.quick && Motion.quick < Motion.standard)
  }
}
