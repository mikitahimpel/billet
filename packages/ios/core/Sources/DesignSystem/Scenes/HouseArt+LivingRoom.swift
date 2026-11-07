import SwiftUI

extension HouseArt {
  static var livingRoom: [SceneMark] {
    var marks: [SceneMark] = [
      Draw.solid(
        Draw.rect(336, 372, 360, 234),
        .linear(
          [Palette.clay, Palette.clayDeep],
          from: CGPoint(x: 696, y: 372),
          to: CGPoint(x: 336, y: 606)
        )
      ),
      Draw.solid(
        Draw.rect(336, 372, 360, 234),
        .glow(Palette.light, opacity: 0.38, center: CGPoint(x: 620, y: 466), radius: 330)
      ),
      Draw.solid(Draw.rect(330, 372, 12, 82), Palette.woodShade),
      Draw.solid(Draw.rect(330, 450, 12, 4), Palette.woodLit),
    ]
    marks += pendantLamp + noteWire + olderNote + letterTrail + sofa + sideTable
    marks += cup(atX: 620, handleSide: -1) + cup(atX: 660, handleSide: 1)
    return marks
  }

  private static var pendantLamp: [SceneMark] {
    [
      Draw.solid(
        Draw.circle(636, 464, 60),
        .glow(Palette.lightWarm, opacity: 0.7, center: CGPoint(x: 636, y: 464), radius: 60)
      ),
      Draw.line("M636 372 V424", Palette.paper, width: 2.5),
      Draw.solid(Draw.circle(636, 464, 11), Palette.lightWarm),
      Draw.solid(Draw.shape("M602 458 L618 424 H654 L670 458 Z"), Palette.green),
      Draw.solid(Draw.shape("M602 458 H670 L654 424 Z"), Palette.greenLit),
    ]
  }

  private static var noteWire: [SceneMark] {
    [
      Draw.line("M348 398 C430 420 520 420 612 394", Palette.paper, width: 2.5),
      Draw.solid(Draw.circle(348, 398, 3.5), Palette.woodLit),
      Draw.solid(Draw.circle(612, 394, 3.5), Palette.woodLit),
    ]
  }

  /// An earlier note, still up: the wall keeps what came through the door.
  private static var olderNote: [SceneMark] {
    Draw.tilted(
      5,
      aroundX: 386,
      y: 442,
      [
        Draw.solid(Draw.rect(358, 412, 56, 62, radius: 3), Palette.paperTurned),
        Draw.line(
          "M386 432 C378 431 376 440 380 445 C386 451 396 447 396 439 C396 432 390 430 385 433",
          Palette.clayDeep,
          width: 2.2
        ),
        Draw.line(
          """
          M386 422 L385 427 M399 428 L395 431 M403 441 L399 441 M397 454 L394 451
          M385 459 L385 454 M374 454 L377 451 M369 441 L373 442 M373 428 L377 431
          """,
          Palette.clayDeep,
          width: 2.2
        ),
        Draw.solid(Draw.rect(378, 401, 7, 17, radius: 2), Palette.woodLit),
      ]
    )
  }

  /// The way a note travels: from the letterbox to the wall.
  private static var letterTrail: [SceneMark] {
    [(302, 530), (322, 521), (343, 514), (364, 508), (385, 503), (406, 499)].map { dot in
      Draw.solid(Draw.circle(dot.0, dot.1, 2.6), Palette.paper)
    }
  }

  private static var sofa: [SceneMark] {
    [
      Draw.solid(Draw.rect(376, 538, 188, 52, radius: 15), Palette.green),
      Draw.solid(Draw.rect(362, 570, 216, 30, radius: 11), Palette.greenShade),
      Draw.solid(Draw.rect(388, 558, 80, 24, radius: 9), Palette.greenLit),
      Draw.solid(Draw.rect(472, 558, 80, 24, radius: 9), Palette.greenLit),
      Draw.solid(Draw.rect(356, 554, 38, 48, radius: 14), Palette.greenBright),
      Draw.solid(Draw.rect(546, 554, 38, 48, radius: 14), Palette.greenLit),
      Draw.solid(
        Draw.shape("M368 600 H384 L381 606 H371 Z M556 600 H572 L569 606 H559 Z"),
        Palette.ink
      ),
      Draw.tilted(
        14,
        aroundX: 452,
        y: 554,
        [Draw.solid(Draw.rect(436, 538, 32, 32, radius: 8), Palette.clayLit)]
      )[0],
      Draw.tilted(
        -14,
        aroundX: 488,
        y: 554,
        [Draw.solid(Draw.rect(472, 538, 32, 32, radius: 8), Palette.gold)]
      )[0],
    ]
  }

  private static var sideTable: [SceneMark] {
    [
      Draw.solid(Draw.rect(594, 556, 92, 9, radius: 3), Palette.wood),
      Draw.solid(Draw.rect(594, 556, 92, 3.5, radius: 1.75), Palette.woodLit),
      Draw.solid(
        Draw.shape("M602 565 H612 L608 606 H600 Z M668 565 H678 L680 606 H672 Z"),
        Palette.woodDeep
      ),
      Draw.solid(Draw.rect(608, 584, 64, 4, radius: 2), Palette.woodDeep),
    ]
  }

  private static func cup(atX x: CGFloat, handleSide side: CGFloat) -> [SceneMark] {
    [
      Draw.solid(Draw.ellipse(x, 553, 20, 4.5), Palette.paperTurned),
      Draw.solid(
        Draw.shape(
          """
          M\(x - 15) 526 C\(x - 15) 538 \(x - 12) 546 \(x - 8) 549 H\(x + 8)
          C\(x + 12) 546 \(x + 15) 538 \(x + 15) 526 Z
          """
        ),
        Palette.paper
      ),
      Draw.line(
        "M\(x + side * 15) 531 C\(x + side * 25) 529 \(x + side * 26) 543 \(x + side * 11) 543",
        Palette.paperTurned,
        width: 4
      ),
      Draw.solid(Draw.ellipse(x, 526, 15, 5), Palette.wood),
      Draw.line(
        "M\(x + side * 2) 514 C\(x + side * 8) 506 \(x - side * 6) 502 \(x - side * 2) 492",
        Palette.paper,
        width: 2.5,
        opacity: 0.5
      ),
    ]
  }
}
