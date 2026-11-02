import CoreGraphics
import Testing

@testable import FeatureHome

@MainActor @Suite struct StyledHomeTests {
  private let size = CGSize(width: 393, height: 852)

  @Test func theTreatChipSitsBelowAndRightOfTheCat() {
    let point = StyledHome.chipPosition(near: CGPoint(x: 200, y: 400), in: size)
    #expect(point.x > 200)
    #expect(point.y > 400)
  }

  @Test func theTreatChipStaysClearOfTheEdgesAndTheBottomControls() {
    let corner = StyledHome.chipPosition(near: CGPoint(x: 390, y: 840), in: size)
    #expect(corner.x <= size.width - 40)
    #expect(corner.y <= size.height - 220)
    let top = StyledHome.chipPosition(near: CGPoint(x: -50, y: -50), in: size)
    #expect(top.x >= 40)
    #expect(top.y >= 120)
  }
}
