import SwiftUI

/// The medium widget's room, not `HouseArt` scaled down: at widget size the house's objects stop
/// reading. It has one art state; only the number on its plate changes.
public enum RoomArt {
  public static let size = CGSize(width: 338, height: 158)

  public static let noteFrame = CGRect(x: 22, y: 22, width: 124, height: 104)
  public static let noteTilt: Double = -3
  public static let plateFrame = CGRect(x: 266, y: 68, width: 56, height: 38)
  public static let nameCenter = CGPoint(x: 294, y: 52)
  public static let captionCenter = CGPoint(x: 294, y: 122)

  public static var art: SceneArt {
    SceneArt(size: size, marks: wall + lamp + table + steam + wire)
  }

  private static var wall: [SceneMark] {
    [
      Draw.solid(
        Draw.rect(0, 0, 338, 158),
        .linear(
          [Palette.clay, Palette.clayNight],
          from: .zero,
          to: CGPoint(x: 338, y: 158)
        )
      ),
      Draw.solid(
        Draw.rect(0, 0, 338, 158),
        .glow(Palette.light, opacity: 0.34, center: CGPoint(x: 214, y: 30), radius: 150)
      ),
      Draw.solid(Draw.rect(0, 142, 338, 16), Palette.ink),
      Draw.solid(Draw.rect(0, 142, 338, 3), Palette.woodLit),
    ]
  }

  private static var lamp: [SceneMark] {
    [
      Draw.solid(Draw.shape("M196 18 L206 3 H222 L232 18 Z"), Palette.green),
      Draw.solid(Draw.shape("M196 18 H232 L222 3 Z"), Palette.greenLit),
      Draw.solid(Draw.circle(214, 20, 4), Palette.lightWarm),
    ]
  }

  private static var table: [SceneMark] {
    [
      Draw.solid(Draw.rect(170, 116, 88, 5, radius: 2), Palette.woodLit),
      Draw.solid(
        Draw.shape("M178 121 H185 L183 142 H178 Z M243 121 H250 L250 142 H245 Z"),
        Palette.ink
      ),
      Draw.solid(
        Draw.shape("M183 100 H205 C205 107 202 112 199 114 H189 C186 112 183 107 183 100 Z"),
        Palette.paper
      ),
      Draw.solid(
        Draw.shape("M223 100 H245 C245 107 242 112 239 114 H229 C226 112 223 107 223 100 Z"),
        Palette.paper
      ),
      Draw.line("M184 103 C177 102 177 111 186 110", Palette.paper, width: 2.4),
      Draw.line("M244 103 C251 102 251 111 242 110", Palette.paper, width: 2.4),
    ]
  }

  /// Two wisps, one from each cup, crossing into one heart.
  private static var steam: [SceneMark] {
    [
      Draw.line(
        "M194 96 C194 90 208 84 214 78 C230 66 250 56 245 44 C240 34 222 34 214 48",
        Palette.lightWarm,
        width: 3.2
      ),
      Draw.line(
        "M234 96 C234 90 220 84 214 78 C198 66 178 56 183 44 C188 34 206 34 214 48",
        Palette.lightWarm,
        width: 3.2
      ),
    ]
  }

  private static var wire: [SceneMark] {
    [
      Draw.line("M-4 6 C44 20 104 20 168 8", Palette.paper, width: 2),
      Draw.solid(Draw.circle(168, 8, 3), Palette.woodLit),
    ]
  }
}
