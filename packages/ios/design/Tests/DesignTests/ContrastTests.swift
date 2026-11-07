import SwiftUI
import Testing

@testable import Design

@Suite struct ContrastTests {
  private func ratio(_ top: Adaptive, over background: Adaptive, _ appearance: Appearance) -> Double
  {
    top.value(appearance).contrast(
      over: background.value(appearance).over(Palette.screen.value(appearance)))
  }

  @Test(arguments: Appearance.allCases)
  func textReadsOnEverySurface(_ appearance: Appearance) {
    for surface in [Palette.screen, Palette.surface, Palette.surfaceRaised] {
      #expect(ratio(Palette.text, over: surface, appearance) >= 7)
      #expect(ratio(Palette.textSecondary, over: surface, appearance) >= 4.5)
      #expect(ratio(Palette.accentText, over: surface, appearance) >= 4.5)
      #expect(ratio(Palette.destructive, over: surface, appearance) >= 4.5)
    }
  }

  @Test func heroInkReadsOnHoney() {
    #expect(Palette.heroInk.contrast(over: Palette.honey) >= 7)
  }

  @Test(arguments: Appearance.allCases)
  func disabledButtonsStayLegible(_ appearance: Appearance) {
    let fill = Palette.disabledFill.value(appearance).over(Palette.screen.value(appearance))
    let onCard = Palette.disabledFill.value(appearance).over(Palette.surface.value(appearance))
    #expect(Palette.disabledText.value(appearance).contrast(over: fill) >= 4.5)
    #expect(Palette.disabledText.value(appearance).contrast(over: onCard) >= 4.5)
  }

  /// Glass controls float over the dark room, a bright room and the city, in either appearance.
  @Test(arguments: Appearance.allCases)
  func glassGlyphsReadOverEveryBackdrop(_ appearance: Appearance) {
    let backdrops = [
      Palette.roomBackdrop, Palette.roomBackdropBright, Palette.cityBackdrop,
      Palette.screen.value(appearance),
    ]
    for backdrop in backdrops {
      let fill = Palette.glassFill.value(appearance).over(backdrop)
      #expect(Palette.glassGlyph.value(appearance).contrast(over: fill) >= 4.5)
      // The unselected label of the segmented control.
      #expect(Palette.glassGlyphSecondary.value(appearance).over(fill).contrast(over: fill) >= 4.5)
      // The selected thumb is a solid surface.
      #expect(
        Palette.text.value(appearance).over(Palette.surface.value(appearance)).contrast(
          over: Palette.surface.value(appearance)) >= 4.5)
    }
  }

  /// On honey the ring does the work; on a dark surface or the dark room the gold face does. On cream the ring
  /// outlines it.
  @Test func coinStandsOutFromEveryBackgroundItSitsOn() {
    #expect(Palette.coinRing.contrast(over: Palette.honey) >= 3)
    #expect(Palette.coinFace.contrast(over: Palette.coinRing) >= 3)
    #expect(Palette.coinRing.contrast(over: Palette.screen.light) >= 3)
    #expect(Palette.coinFace.contrast(over: Palette.surface.dark) >= 3)
    #expect(Palette.coinFace.contrast(over: Palette.glassFill.dark.over(Palette.roomBackdrop)) >= 3)
  }
}

@Suite struct SheetChromeTests {
  @Test func closeIsLeadingWhenTheSheetConfirmsAndTrailingWhenItOnlyInforms() {
    #expect(BilletSheet<EmptyView>.ClosePlacement(confirms: true) == .leading)
    #expect(BilletSheet<EmptyView>.ClosePlacement(confirms: false) == .trailing)
  }

  @Test func oneInsetMakesThumbAndTrackConcentric() {
    #expect(Size.control - 2 * GlassSegmented<Int>.inset == 36)
  }
}
