import DesignSystem
import Testing

@testable import PetSceneReality

@Suite struct OnboardingTagTests {
  init() { try? BilletFonts.register() }

  @Test(arguments: ["ABCDEFGHJK", "WWWWWWWWWW", "2345", "M"])
  func theCodeFitsInsideTheBorder(code: String) {
    let size = OnboardingTag.codeSize(code)
    #expect(size <= 150)
    #expect(
      OnboardingTag.measure(code, font: OnboardingTag.codeFont(size: size)) <= OnboardingTag
        .codeRoom + 0.5)
  }

  @Test func aShortCodeKeepsItsFullSize() {
    #expect(OnboardingTag.codeSize("2345") == 150)
  }
}
