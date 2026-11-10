import CoreGraphics
import Testing

@testable import Design

@Suite struct LayoutTests {
  @Test func gridColumnsFillTheWidthWithTheGutterBetween() {
    let grid = EqualGridLayout(columns: 2, spacing: Space.m)
    let width: CGFloat = 335
    let column = grid.columnWidth(width)
    #expect(column * 2 + Space.m == width)
  }

  @Test func oneColumnTakesTheWholeWidth() {
    #expect(EqualGridLayout(columns: 1, spacing: Space.m).columnWidth(200) == 200)
  }

  @Test func aNarrowWidthNeverGivesANegativeColumn() {
    #expect(EqualGridLayout(columns: 3, spacing: Space.m).columnWidth(10) == 0)
  }

  @Test func calloutPointerStaysOnTheEdge() {
    #expect(CalloutPointer(edge: .top, position: 4).position == 1)
    #expect(CalloutPointer(edge: .bottom, position: -1).position == 0)
  }

  @Test func cornersAreTheRadiusScale() {
    #expect(Corner.card.radius == Radius.card)
    #expect(Corner.inner.radius == Radius.inner)
    #expect(Corner.control.radius == Radius.control)
  }
}
