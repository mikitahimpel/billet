import SwiftUI
import Testing

@testable import Design

/// Every look passes every pair, in both appearances.
@Suite struct ContrastTests {
  struct Case: CustomTestStringConvertible {
    let look: Look
    let appearance: Appearance
    var tones: Tones { Palette.tones(look) }
    var testDescription: String { "\(look) \(appearance)" }

    static let all = Look.allCases.flatMap { look in
      Appearance.allCases.map { Case(look: look, appearance: $0) }
    }
  }

  private func ratio(_ top: Adaptive, over background: Adaptive, _ c: Case) -> Double {
    top.value(c.appearance).contrast(
      over: background.value(c.appearance).over(c.tones.screen.value(c.appearance)))
  }

  @Test(arguments: Case.all)
  func textReadsOnEverySurface(_ c: Case) {
    let t = c.tones
    let surfaces = [t.screen, t.surface, t.surfaceRaised, t.surfaceTop, t.surfaceBottom]
    for surface in surfaces {
      #expect(ratio(t.text, over: surface, c) >= 7)
      #expect(ratio(t.textSecondary, over: surface, c) >= 4.5)
      #expect(ratio(t.accentText, over: surface, c) >= 4.5)
      #expect(ratio(t.destructive, over: surface, c) >= 4.5)
    }
  }

  /// The hero card carries words and numbers, never accent or destructive text.
  @Test(arguments: Case.all)
  func wordsReadOnTheWarmCard(_ c: Case) {
    let t = c.tones
    for surface in [t.warmTop, t.warmBottom, t.warmGlow] {
      #expect(ratio(t.text, over: surface, c) >= 6)
      #expect(ratio(t.textSecondary, over: surface, c) >= 4.5)
    }
  }

  @Test(arguments: Look.allCases)
  func heroInkReadsOnHoney(_ look: Look) {
    let t = Palette.tones(look)
    #expect(t.heroInk.contrast(over: t.honey) >= 7)
    #expect(t.heroInk.contrast(over: t.honeyLight) >= 7)
  }

  @Test(arguments: Case.all)
  func disabledButtonsStayLegible(_ c: Case) {
    let t = c.tones
    let fill = t.disabledFill.value(c.appearance).over(t.screen.value(c.appearance))
    let onCard = t.disabledFill.value(c.appearance).over(t.surface.value(c.appearance))
    #expect(t.disabledText.value(c.appearance).contrast(over: fill) >= 4.5)
    #expect(t.disabledText.value(c.appearance).contrast(over: onCard) >= 4.5)
  }

  /// Glass controls float over the dark room, a bright room and the city, in either appearance.
  @Test(arguments: Case.all)
  func glassGlyphsReadOverEveryBackdrop(_ c: Case) {
    let t = c.tones
    let backdrops = [
      t.roomBackdrop, Palette.roomBackdropBright, Palette.cityBackdrop,
      t.screen.value(c.appearance),
    ]
    for backdrop in backdrops {
      let fill = t.glassFill.value(c.appearance).over(backdrop)
      #expect(t.glassGlyph.value(c.appearance).contrast(over: fill) >= 4.5)
      // The unselected label of the segmented control.
      #expect(t.glassGlyphSecondary.value(c.appearance).over(fill).contrast(over: fill) >= 4.5)
      // The selected tab or room: the selection laid on the glass.
      let selected = t.glassSelection.value(c.appearance).over(fill)
      #expect(t.glassGlyph.value(c.appearance).contrast(over: selected) >= 4.5)
    }
  }

  /// On honey the ring does the work; on a dark surface or the dark room the gold face does.
  @Test(arguments: Look.allCases)
  func coinStandsOutFromEveryBackgroundItSitsOn(_ look: Look) {
    let t = Palette.tones(look)
    #expect(t.heroInk.contrast(over: t.honey) >= 3)
    #expect(Palette.coinFace.contrast(over: t.heroInk) >= 3)
    #expect(t.heroInk.contrast(over: t.screen.light) >= 3)
    #expect(Palette.coinFace.contrast(over: t.surface.dark) >= 3)
    #expect(Palette.coinFace.contrast(over: t.glassFill.dark.over(t.roomBackdrop)) >= 3)
  }

  /// The looks differ only where the night differs: the cream of the light appearance is shared.
  @Test func duskKeepsTheLightCream() {
    #expect(Palette.dusk.screen.light == Palette.classic.screen.light)
    #expect(Palette.dusk.text.light == Palette.classic.text.light)
    #expect(Palette.dusk.surface.light == Palette.classic.surface.light)
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
