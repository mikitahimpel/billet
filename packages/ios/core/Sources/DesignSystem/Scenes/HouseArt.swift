import SwiftUI

/// The house in cross-section on its night hill: the full scene, for large surfaces only.
/// Small surfaces get `RoomArt`, a separate composition.
public enum HouseArt {
  public static let size = CGSize(width: 1030, height: 704)

  /// Where a note hangs on the living-room wall.
  public static let noteFrame = CGRect(x: 426, y: 414, width: 150, height: 119)
  public static let noteTilt: Double = -3
  /// The centre of the plate above the front door.
  public static let plateCenter = CGPoint(x: 276, y: 415)
  /// The centre of the number inside the next-room outline.
  public static let nextRoomLabelCenter = CGPoint(x: 776, y: 538)

  public static func art(for stage: HouseStage) -> SceneArt {
    var marks = sky
    if stage >= .chimney {
      marks += chimney
    }
    if stage == .chimney {
      marks += nextRoomOutline
    }
    if stage >= .newRoom {
      marks += newRoom
    }
    if stage >= .tree {
      marks += tree
    }
    if stage >= .garden {
      marks += garden
    }
    for layer in [structure, bedroom, roof, hall, livingRoom, hill] {
      marks += layer
    }
    return SceneArt(size: size, marks: marks)
  }

  // MARK: The night

  private static var sky: [SceneMark] {
    [
      Draw.solid(
        Draw.rect(0, 0, 1030, 704),
        .linear(
          [Palette.skyLit, Palette.greenDeep, Palette.skyNight],
          from: CGPoint(x: 1030, y: 0),
          to: CGPoint(x: 0, y: 704)
        )
      ),
      Draw.solid(
        Draw.rect(0, 0, 1030, 704),
        .glow(Palette.light, opacity: 0.3, center: CGPoint(x: 430, y: 390), radius: 520)
      ),
      Draw.sparkle(206, 112, size: 13, Palette.gold),
      Draw.sparkle(238, 138, size: 9, Palette.paper, opacity: 0.8),
      Draw.sparkle(868, 92, size: 12, Palette.gold),
      Draw.sparkle(958, 178, size: 7, Palette.paper, opacity: 0.6),
      Draw.sparkle(64, 96, size: 8, Palette.gold, opacity: 0.85),
      Draw.sparkle(82, 330, size: 6, Palette.paper, opacity: 0.55),
      Draw.solid(Draw.circle(770, 200, 3), Palette.paper, opacity: 0.45),
      Draw.solid(Draw.circle(348, 46, 2.5), Palette.paper, opacity: 0.45),
      Draw.solid(Draw.circle(978, 48, 3), Palette.paper, opacity: 0.4),
    ]
  }

  private static var hill: [SceneMark] {
    let line = "M0 672 C90 640 200 622 430 622 C660 622 800 650 1030 668"
    return [
      Draw.solid(Draw.shape(line + " V704 H0 Z"), Palette.hill),
      Draw.line(line, Palette.greenLit, width: 4),
    ]
  }

  // MARK: What grows

  private static var garden: [SceneMark] {
    let pickets = [34, 56, 78, 100, 122].map { (x: CGFloat) in
      Draw.solid(
        Draw.shape("M\(x) 680 V620 L\(x + 5) 612 L\(x + 10) 620 V680 Z"),
        Palette.woodLit
      )
    }
    return Draw.tilted(
      -8,
      aroundX: 80,
      y: 640,
      [
        Draw.line("M74 668 C74 640 70 612 76 584", Palette.greenLit, width: 3.5),
        Draw.line("M98 668 C98 636 100 612 92 574", Palette.greenLit, width: 3.5),
        Draw.solid(Draw.circle(76, 578, 10), Palette.gold),
        Draw.solid(Draw.circle(76, 578, 4), Palette.clayDeep),
        Draw.solid(Draw.circle(91, 568, 11), Palette.clayLit),
        Draw.solid(Draw.circle(91, 568, 4), Palette.light),
        Draw.solid(Draw.rect(28, 628, 104, 5, radius: 2), Palette.wood),
        Draw.solid(Draw.rect(28, 644, 104, 5, radius: 2), Palette.wood),
      ] + pickets
    )
  }

  private static var tree: [SceneMark] {
    [
      Draw.solid(Draw.circle(906, 503, 43), Palette.green),
      Draw.solid(Draw.circle(981, 509, 37), Palette.green),
      Draw.solid(Draw.circle(944, 455, 54), Palette.green),
      Draw.solid(
        Draw.shape("M936 690 C936 628 921 586 912 535 L923 532 C933 583 946 628 949 690 Z"),
        Palette.wood
      ),
      Draw.solid(
        Draw.shape("M943 690 C946 628 960 586 971 540 L982 544 C971 591 959 628 957 690 Z"),
        Palette.woodShade
      ),
      Draw.solid(Draw.circle(920, 484, 37), Palette.greenLit),
      Draw.solid(Draw.circle(959, 445, 34), Palette.greenLit),
      Draw.solid(Draw.circle(975, 495, 24), Palette.green),
      Draw.solid(Draw.circle(909, 471, 13), Palette.greenBright),
      Draw.solid(Draw.circle(947, 429, 11), Palette.greenBright),
    ]
  }

  private static var chimney: [SceneMark] {
    [
      Draw.solid(
        Draw.circle(627, 56, 120),
        .glow(Palette.lightWarm, opacity: 0.12, center: CGPoint(x: 627, y: 56), radius: 120)
      ),
      Draw.line(
        "M614 124 C614 112 622 106 627 98 C648 76 704 58 698 34 C692 12 644 12 627 46",
        Palette.lightWarm,
        width: 6
      ),
      Draw.line(
        "M640 124 C640 112 632 106 627 98 C606 76 550 58 556 34 C562 12 610 12 627 46",
        Palette.lightWarm,
        width: 6
      ),
      Draw.solid(Draw.rect(606, 126, 16, 22, radius: 2), Palette.clayLit),
      Draw.solid(Draw.rect(632, 126, 16, 22, radius: 2), Palette.clayLit),
      Draw.solid(Draw.rect(604, 124, 20, 6, radius: 2), Palette.clay),
      Draw.solid(Draw.rect(630, 124, 20, 6, radius: 2), Palette.clay),
      Draw.solid(Draw.rect(598, 150, 56, 80), Palette.clayDeep),
      Draw.solid(Draw.rect(626, 150, 28, 80), Palette.clay),
      Draw.solid(Draw.rect(592, 146, 68, 8, radius: 3), Palette.woodLit),
    ]
  }

  private static var nextRoomOutline: [SceneMark] {
    [
      Draw.solid(
        Draw.shape("M716 468 L776 428 L836 468 V672 H716 Z"),
        Palette.lightWarm,
        opacity: 0.06
      ),
      Draw.line("M712 470 L776 428 L840 470 V672", Palette.paper, width: 3, dash: [10, 9]),
    ]
  }

  private static var newRoom: [SceneMark] {
    [
      Draw.solid(Draw.rect(710, 468, 126, 138), Palette.clayDeep),
      Draw.solid(
        Draw.rect(710, 468, 126, 138),
        .glow(Palette.light, opacity: 0.4, center: CGPoint(x: 773, y: 500), radius: 120)
      ),
      Draw.solid(Draw.rect(836, 468, 12, 152), Palette.woodShade),
      Draw.solid(Draw.rect(710, 606, 138, 14), Palette.woodShade),
      Draw.solid(Draw.rect(710, 606, 138, 4), Palette.woodLit),
      Draw.solid(Draw.rect(710, 620, 138, 50), Palette.ink),
      Draw.solid(
        Draw.shape("M696 470 L776 416 L860 470 V488 L776 434 L696 488 Z"),
        Palette.clayLit
      ),
      Draw.solid(Draw.circle(773, 508, 22), Palette.skyNight),
      Draw.sparkle(766, 502, size: 6, Palette.gold),
      Draw.line("M773 486 V530 M751 508 H795", Palette.woodLit, width: 3),
      Draw.line(
        "M773 486 C785 486 795 496 795 508 C795 520 785 530 773 530",
        Palette.woodLit,
        width: 4
      ),
      Draw.line(
        "M773 530 C761 530 751 520 751 508 C751 496 761 486 773 486",
        Palette.woodLit,
        width: 4
      ),
      Draw.solid(Draw.rect(726, 566, 40, 26, radius: 8), Palette.greenLit),
      Draw.solid(Draw.rect(722, 544, 16, 62, radius: 7), Palette.green),
      Draw.solid(Draw.rect(782, 566, 40, 26, radius: 8), Palette.gold),
      Draw.solid(Draw.rect(810, 544, 16, 62, radius: 7), Palette.woodLit),
    ]
  }

  // MARK: The house

  private static var structure: [SceneMark] {
    [
      Draw.solid(Draw.rect(150, 280, 14, 340), Palette.woodShade),
      Draw.solid(Draw.rect(696, 280, 14, 340), Palette.woodShade),
      Draw.solid(Draw.rect(150, 620, 560, 50), Palette.ink),
    ]
  }

  private static var bedroom: [SceneMark] {
    let gable = Draw.shape("M164 358 V278 L430 118 L696 278 V358 Z")
    var marks: [SceneMark] = [
      Draw.solid(
        gable,
        .linear(
          [Palette.woodShade, Palette.wood],
          from: CGPoint(x: 430, y: 118),
          to: CGPoint(x: 430, y: 358)
        )
      ),
      Draw.solid(
        gable,
        .glow(Palette.light, opacity: 0.55, center: CGPoint(x: 299, y: 304), radius: 190)
      ),
      Draw.solid(
        gable,
        .glow(Palette.light, opacity: 0.55, center: CGPoint(x: 561, y: 304), radius: 190)
      ),
    ]
    marks += roundWindow + suitcases + plant
    marks += bed + bedsideLamp(at: 0) + bedsideLamp(at: 262)
    return marks
  }

  private static var roundWindow: [SceneMark] {
    [
      Draw.solid(Draw.circle(430, 196, 31), Palette.skyNight),
      Draw.sparkle(420, 186, size: 7, Palette.gold),
      Draw.sparkle(441, 206, size: 5, Palette.paper),
      Draw.line("M430 165 V227 M399 196 H461", Palette.woodLit, width: 3),
      SceneMark(
        path: Draw.circle(430, 196, 31),
        paint: .solid(Palette.woodLit),
        style: .stroke(StrokeStyle(lineWidth: 6)),
        opacity: 1
      ),
    ]
  }

  private static var suitcases: [SceneMark] {
    [
      Draw.solid(Draw.rect(180, 336, 72, 22, radius: 5), Palette.clay),
      Draw.solid(Draw.rect(188, 316, 56, 20, radius: 5), Palette.green),
      Draw.line("M206 316 V311 H226 V316", Palette.clayDeep, width: 3),
      Draw.solid(Draw.rect(198, 340, 6, 14, radius: 1), Palette.paperTurned),
      Draw.solid(Draw.rect(228, 340, 6, 14, radius: 1), Palette.paperTurned),
    ]
  }

  private static var plant: [SceneMark] {
    [
      Draw.line("M628 330 C616 312 610 298 614 282", Palette.green, width: 9),
      Draw.line("M632 330 C644 316 652 306 656 290", Palette.greenLit, width: 9),
      Draw.line("M630 330 C630 312 630 296 634 274", Palette.green, width: 7),
      Draw.solid(Draw.shape("M612 328 H648 L642 358 H618 Z"), Palette.clayLit),
      Draw.solid(Draw.shape("M612 328 H628 L626 358 H618 Z"), Palette.clay),
    ]
  }

  private static var bed: [SceneMark] {
    let heart = Draw.shape(
      """
      M430 296 C414 285 416 272 424 272 C427 272 430 275 430 278
      C430 275 433 272 436 272 C444 272 446 285 430 296 Z
      """
    )
    .applying(CGAffineTransform(translationX: -430, y: -296))
    .applying(CGAffineTransform(scaleX: 1.3, y: 1.3))
    .applying(CGAffineTransform(translationX: 430, y: 286))

    let pillows =
      Draw.tilted(
        3,
        aroundX: 390,
        y: 312,
        [
          Draw.solid(Draw.rect(350, 296, 78, 32, radius: 14), Palette.paperTurned),
          Draw.solid(Draw.rect(350, 294, 78, 27, radius: 13), Palette.paper),
        ]
      )
      + Draw.tilted(
        -3,
        aroundX: 470,
        y: 312,
        [
          Draw.solid(Draw.rect(432, 296, 78, 32, radius: 14), Palette.paperTurned),
          Draw.solid(Draw.rect(432, 294, 78, 27, radius: 13), Palette.paper),
        ]
      )

    return [
      Draw.solid(Draw.rect(336, 238, 188, 120, radius: 22), Palette.woodDeep),
      Draw.solid(Draw.rect(336, 238, 188, 8, radius: 4), Palette.wood),
      Draw.solid(heart, Palette.light),
      Draw.solid(Draw.rect(346, 346, 10, 12), Palette.ink),
      Draw.solid(Draw.rect(504, 346, 10, 12), Palette.ink),
    ] + pillows + [
      Draw.solid(Draw.rect(338, 322, 184, 28, radius: 9), Palette.clay),
      Draw.solid(Draw.rect(338, 322, 184, 11, radius: 5.5), Palette.clayLit),
    ]
  }

  private static func bedsideLamp(at offset: CGFloat) -> [SceneMark] {
    let x = 299 + offset
    return [
      Draw.solid(Draw.rect(x - 27, 320, 54, 7, radius: 3), Palette.wood),
      Draw.solid(Draw.rect(x - 27, 320, 54, 3, radius: 1.5), Palette.woodLit),
      Draw.solid(
        Draw.shape(
          """
          M\(x - 21) 327 H\(x - 11) L\(x - 13) 358 H\(x - 19) Z
          M\(x + 11) 327 H\(x + 21) L\(x + 19) 358 H\(x + 13) Z
          """
        ),
        Palette.woodDeep
      ),
      Draw.solid(
        Draw.circle(x, 300, 48),
        .glow(Palette.lightWarm, opacity: 0.7, center: CGPoint(x: x, y: 300), radius: 48)
      ),
      Draw.solid(Draw.rect(x - 2, 306, 4, 14), Palette.woodDeep),
      Draw.solid(Draw.circle(x, 302, 7), Palette.lightWarm),
      Draw.solid(
        Draw.shape("M\(x - 20) 298 L\(x - 12) 274 H\(x + 12) L\(x + 20) 298 Z"),
        Palette.green
      ),
      Draw.solid(Draw.shape("M\(x - 20) 298 H\(x + 20) L\(x + 12) 274 Z"), Palette.greenLit),
    ]
  }

  private static var roof: [SceneMark] {
    [
      Draw.solid(Draw.shape("M124 268 L430 84 V118 L124 302 Z"), Palette.clay),
      Draw.solid(Draw.shape("M430 84 L736 268 V302 L430 118 Z"), Palette.clayLit),
      Draw.line("M136 278 L430 101", Palette.clayDeep, width: 3, dash: [15, 12]),
      Draw.line("M430 101 L724 278", Palette.clay, width: 3, dash: [15, 12]),
      Draw.line("M164 278 L430 118 L696 278", Palette.woodLit, width: 3),
      Draw.solid(Draw.rect(150, 358, 560, 14), Palette.woodShade),
      Draw.solid(Draw.rect(150, 358, 560, 5), Palette.woodLit),
    ]
  }

  private static var hall: [SceneMark] {
    var marks: [SceneMark] = [
      Draw.solid(
        Draw.rect(164, 372, 172, 234),
        .linear(
          [Palette.greenShade, Palette.greenDeep],
          from: CGPoint(x: 250, y: 372),
          to: CGPoint(x: 250, y: 606)
        )
      ),
      Draw.solid(
        Draw.rect(164, 372, 172, 234),
        .glow(Palette.lightWarm, opacity: 0.12, center: CGPoint(x: 250, y: 372), radius: 230)
      ),
      Draw.solid(Draw.rect(164, 606, 532, 14), Palette.woodShade),
      Draw.solid(Draw.rect(164, 606, 532, 5), Palette.woodLit),
      Draw.solid(Draw.rect(170, 438, 60, 6, radius: 3), Palette.wood),
      Draw.solid(Draw.rect(170, 438, 60, 2.5, radius: 1.25), Palette.woodLit),
    ]
    marks += frontDoor
    marks += coat(atX: 185, length: 524, Palette.clayLit, trim: Palette.clayDeep, tilt: -2)
    marks += coat(atX: 217, length: 514, Palette.woodLit, trim: Palette.wood, tilt: 2)
    marks += [
      Draw.solid(
        Draw.shape("M172 606 V597 C172 594 178 594 180 597 L188 601 C190 603 190 606 188 606 Z"),
        Palette.clayLit
      ),
      Draw.solid(
        Draw.shape("M194 606 V597 C194 594 200 594 202 597 L210 601 C212 603 212 606 210 606 Z"),
        Palette.woodLit
      ),
    ]
    return marks
  }

  private static func arch(left: CGFloat, right: CGFloat, spring: CGFloat) -> Path {
    let radius = (right - left) / 2
    let lift = radius * 0.5523
    let middle = left + radius
    let top = spring - radius
    return Draw.shape(
      """
      M\(left) 606 V\(spring)
      C\(left) \(spring - lift) \(middle - lift) \(top) \(middle) \(top)
      C\(middle + lift) \(top) \(right) \(spring - lift) \(right) \(spring)
      V606 Z
      """
    )
  }

  private static var frontDoor: [SceneMark] {
    [
      Draw.solid(arch(left: 228, right: 324, spring: 492), Palette.wood),
      Draw.solid(arch(left: 236, right: 316, spring: 492), Palette.clay),
      Draw.solid(Draw.rect(246, 486, 24, 44, radius: 4), Palette.clayDeep),
      Draw.solid(Draw.rect(282, 486, 24, 44, radius: 4), Palette.clayDeep),
      Draw.solid(Draw.circle(306, 570, 4.5), Palette.gold),
      Draw.solid(Draw.rect(252, 546, 48, 16, radius: 3), Palette.gold),
      Draw.solid(Draw.rect(257, 549, 38, 5, radius: 1), Palette.ink),
      Draw.tilted(
        -6,
        aroundX: 277,
        y: 552,
        [Draw.solid(Draw.rect(264, 530, 26, 23, radius: 1.5), Palette.paper)]
      )[0],
      Draw.solid(Draw.rect(255, 553, 42, 7, radius: 2), Palette.gold),
      Draw.solid(Draw.rect(240, 600, 72, 6, radius: 2), Palette.clayLit),
    ]
  }

  private static func coat(
    atX x: CGFloat,
    length: CGFloat,
    _ cloth: Swatch,
    trim: Swatch,
    tilt: Double
  ) -> [SceneMark] {
    let hem = length
    let cuff = length - 8
    return Draw.tilted(
      tilt,
      aroundX: x,
      y: 446,
      [
        Draw.solid(
          Draw.shape(
            """
            M\(x - 7) 446 L\(x - 13) 450 L\(x - 15) 462 L\(x - 17) \(cuff) L\(x - 10) \(cuff + 1)
            L\(x - 9) 470 L\(x - 9) \(hem) H\(x + 8) L\(x + 8) 470 L\(x + 9) \(cuff + 1)
            L\(x + 16) \(cuff) L\(x + 14) 462 L\(x + 12) 450 L\(x + 6) 446 L\(x) 460 Z
            """
          ),
          cloth
        ),
        Draw.line("M\(x - 7) 446 L\(x) 460 L\(x + 6) 446", trim, width: 3),
        Draw.solid(Draw.circle(x, 474, 1.8), trim),
        Draw.solid(Draw.circle(x, 490, 1.8), trim),
      ]
    )
  }
}
