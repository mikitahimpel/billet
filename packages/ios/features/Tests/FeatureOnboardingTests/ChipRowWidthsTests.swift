import Foundation
import Testing

@testable import FeatureOnboarding

/// The pronoun chips on the smallest iPhone: "They / them" is wider than a third of the row.
@Suite struct ChipRowWidthsTests {
  @Test func chipsThatFitAThirdShareTheRowEqually() {
    let widths = ChipRowWidths.widths(ideal: [102, 92, 110], available: 400, spacing: 8)
    #expect(widths == [128, 128, 128])
  }

  @Test func aChipWiderThanAThirdKeepsItsOwnWidthAndTheRestIsSharedOut() {
    let widths = ChipRowWidths.widths(ideal: [102, 92, 124], available: 335, spacing: 8)
    #expect(widths.map { $0.rounded() } == [102, 92, 124])
    #expect(zip(widths, [102, 92, 124]).allSatisfy { $0 >= $1 }, "no label is cut")
    #expect(abs(widths.reduce(0, +) + 16 - 335) < 0.01, "the row is filled")
  }

  @Test func aRowThatIsTooNarrowGivesEachChipItsOwnWidth() {
    let widths = ChipRowWidths.widths(ideal: [102, 92, 124], available: 300, spacing: 8)
    #expect(widths == [102, 92, 124])
  }

  @Test func noChipsTakeNoWidth() {
    #expect(ChipRowWidths.widths(ideal: [], available: 300, spacing: 8).isEmpty)
  }
}
