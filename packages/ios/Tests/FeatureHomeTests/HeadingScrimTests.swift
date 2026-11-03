import DesignSystem
import Testing

@testable import FeatureHome

@Suite struct HeadingScrimTests {
  @Test func theWordsKeepAAContrastWithWhiteBehindTheScrim() {
    let ratio = Contrast.ratio(Palette.paper, HeadingScrim.brightestBehindWords)
    #expect(ratio >= ContrastFloor.text.rawValue)
  }
}
