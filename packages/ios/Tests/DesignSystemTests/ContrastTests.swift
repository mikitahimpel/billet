import Testing

@testable import DesignSystem

/// A pair that really appears, named for where. Glow-lit grounds are the worst pixel measured on
/// the rendered board, because the light moves a wall off its token.
struct Pair: CustomTestStringConvertible, Sendable {
  let name: String
  let foreground: Swatch
  let background: Swatch
  let floor: ContrastFloor

  var testDescription: String { name }
}

func text(_ name: String, _ foreground: Swatch, on background: Swatch) -> Pair {
  Pair(name: name, foreground: foreground, background: background, floor: .text)
}

func mark(_ name: String, _ foreground: Swatch, on background: Swatch) -> Pair {
  Pair(name: name, foreground: foreground, background: background, floor: .mark)
}

func rung(_ name: String, _ upper: Swatch, on lower: Swatch) -> Pair {
  Pair(name: name, foreground: upper, background: lower, floor: .rung)
}

let litLivingWall = Swatch(0xAB7D46)
let hallWall = Swatch(0x1C4032)
let widgetLitWall = Swatch(0xAD6E47)
let widgetNameWall = Swatch(0x955537)
let widgetCaptionWall = Swatch(0x77402B)
let canvasWall = Swatch(0x7E462D)
let skyAtHeart = Swatch(0x2C5A44)
let skyAtNextRoom = Swatch(0x37563C)
let lockGlass = Swatch(0x365D4E)
let liveActivityTitleGround = Swatch(0x664029)
let liveActivityGround = Swatch(0x623D27)

let textPairs: [Pair] = [
  text("cream on page", Palette.paper, on: Palette.page),
  text("cream on raised", Palette.paper, on: Palette.raised),
  text("cream on raised top", Palette.paper, on: Palette.raisedTop),
  text("muted on page", Palette.muted, on: Palette.page),
  text("muted on raised", Palette.muted, on: Palette.raised),
  text("muted on raised top", Palette.muted, on: Palette.raisedTop),
  text("numeral on plate", Palette.gold, on: Palette.plate),
  text("turned cream on sky", Palette.paperTurned, on: Palette.sky),
  text("turned cream on meadow", Palette.paperTurned, on: Palette.meadow),
  text("muted on deep page", Palette.muted, on: Palette.pageDeep),
  text("muted on sky", Palette.muted, on: Palette.sky),
  text("Send label on gold", Palette.ink, on: Palette.gold),
  text("ink on paper", Palette.ink, on: Palette.paper),
  text("wordmark on hill", Palette.paper, on: Palette.hill),
  text("widget name on wall", Palette.paper, on: widgetNameWall),
  text("widget caption on wall", Palette.paper, on: widgetCaptionWall),
  text("canvas title on lit wall", Palette.paper, on: canvasWall),
  text("lock text on glass", Swatch(0xFFFFFF), on: lockGlass),
  text("Live Activity title", Palette.paper, on: liveActivityTitleGround),
  text("Live Activity subline", Palette.paperTurned, on: liveActivityGround),
  text("Live Activity numeral", Palette.light, on: liveActivityGround),
]

let markPairs: [Pair] = [
  mark("heart smoke on sky", Palette.lightWarm, on: skyAtHeart),
  mark("next-room dashes", Palette.paper, on: skyAtNextRoom),
  mark("next-room number", Palette.gold, on: skyAtNextRoom),
  mark("wire on lit wall", Palette.paper, on: litLivingWall),
  mark("clay coat on hall", Palette.clayLit, on: hallWall),
  mark("wood coat on hall", Palette.woodLit, on: hallWall),
  mark("widget steam", Palette.lightWarm, on: widgetLitWall),
  mark("hill edge", Palette.greenLit, on: Palette.hill),
  mark("ink on paper", Palette.ink, on: Palette.paper),
  mark("clay ink on paper", Palette.clayLit, on: Palette.paper),
  mark("green ink on paper", Palette.greenLit, on: Palette.paper),
  mark("gold ink on paper", Palette.inkGold, on: Palette.paper),
  mark("clay swatch on tray", Palette.clayLit, on: Palette.raised),
  mark("green swatch on tray", Palette.greenLit, on: Palette.raised),
  mark("gold swatch on tray", Palette.inkGold, on: Palette.raised),
  mark(
    "ink swatch ring on tray",
    Palette.paper.composited(over: Palette.raised, opacity: 0.45),
    on: Palette.raised
  ),
  mark("tool icon on tray", Palette.paper, on: Palette.raised),
]

let rungPairs: [Pair] = [
  rung("page to raised", Palette.raised, on: Palette.page),
  rung("raised to raised top", Palette.raisedTop, on: Palette.raised),
]

@Suite struct ContrastTests {
  @Test func knownRatios() {
    #expect(abs(Contrast.ratio(Swatch(0x000000), Swatch(0xFFFFFF)) - 21) < 0.001)
    #expect(Contrast.ratio(Palette.gold, Palette.gold) == 1)
    #expect(abs(Contrast.relativeLuminance(of: Swatch(0x808080)) - 0.2159) < 0.0001)
  }

  @Test func compositingFlattensOntoTheGround() {
    #expect(Swatch(0xFFFFFF).composited(over: Swatch(0x000000), opacity: 0.5) == Swatch(0x808080))
    #expect(Palette.gold.composited(over: Palette.page, opacity: 1) == Palette.gold)
  }

  @Test func floorsAreTheOnesTheProjectChose() {
    #expect(ContrastFloor.text.rawValue == 4.5)
    #expect(ContrastFloor.mark.rawValue == 3)
    #expect(ContrastFloor.rung.rawValue == 1.15)
  }

  @Test(arguments: textPairs + markPairs + rungPairs)
  func pairClearsItsFloor(_ pair: Pair) {
    let ratio = Contrast.ratio(pair.foreground, pair.background)
    #expect(
      ratio >= pair.floor.rawValue,
      "\(pair.name) is \(ratio):1 against a floor of \(pair.floor.rawValue)"
    )
  }

  @Test func rawGoldFailsOnPaperWhichIsWhyInkGoldExists() {
    #expect(Contrast.ratio(Palette.gold, Palette.paper) < ContrastFloor.mark.rawValue)
  }
}
