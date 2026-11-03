import DesignSystem
import Testing

@testable import FeatureHome

@MainActor
@Suite struct HeadingScrimTests {
  @Test func theWordsKeepAAContrastWithWhiteBehindTheScrim() {
    let ratio = Contrast.ratio(Palette.paper, HeadingScrim.brightestBehindWords)
    #expect(ratio >= ContrastFloor.text.rawValue)
  }
}
