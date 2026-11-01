import SwiftUI

/// A stand-in for a real note in previews: a wobbly coffee cup and "see you at 7".
/// Real notes come from `Ink`, which `DesignSystem` does not depend on.
public enum SampleDrawing {
  public static let size = CGSize(width: 340, height: 270)

  public static var art: SceneArt {
    SceneArt(size: size, marks: [scribble, cup, words])
  }

  private static func offset(_ data: String, x: CGFloat, y: CGFloat) -> Path {
    ScenePath.parse(data).applying(CGAffineTransform(translationX: x, y: y))
  }

  private static func ink(_ path: Path, _ swatch: Swatch, width: CGFloat) -> SceneMark {
    SceneMark(
      path: path,
      paint: .solid(swatch),
      style: .stroke(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)),
      opacity: 1
    )
  }

  private static var scribble: SceneMark {
    ink(
      offset(
        "M94 112 L156 104 L98 126 L160 116 L106 140 L154 130 L116 152 L146 146",
        x: 45,
        y: -6
      ),
      Palette.clayLit,
      width: 7
    )
  }

  private static var cup: SceneMark {
    ink(
      offset(
        """
        M72 80 C92 66 150 62 174 76 C184 84 150 96 118 96 C92 96 62 92 72 80
        M74 84 C72 108 78 138 90 156 C98 168 146 170 158 156 C170 138 176 104 174 78
        M173 98 C200 88 214 112 197 130 C188 140 172 142 163 139
        M58 172 C90 187 156 187 194 169
        M104 54 C94 42 114 34 104 20 M138 52 C128 40 150 32 140 14
        """,
        x: 45,
        y: -6
      ),
      Palette.ink,
      width: 5.5
    )
  }

  private static var words: SceneMark {
    ink(
      offset(
        """
        M44 212 C38 206 30 208 32 214 C34 220 46 220 44 228 C42 234 32 234 28 229
        M54 222 C62 222 70 218 68 212 C66 206 54 208 52 218 C50 230 62 236 72 229
        M80 222 C88 222 96 218 94 212 C92 206 80 208 78 218 C76 230 88 236 98 229
        M120 210 C118 222 122 230 130 228 C136 226 140 218 140 209
        C142 226 140 242 134 250 C128 256 120 250 124 244
        M160 210 C150 208 146 222 150 229 C156 236 168 230 168 219 C168 211 162 208 156 211
        M178 210 C176 222 178 232 186 230 C192 228 196 220 197 210 C196 220 197 230 204 231
        M240 212 C230 206 222 218 224 226 C226 234 238 232 242 222
        C242 216 242 212 242 210 C242 222 243 230 250 232
        M262 198 C260 212 260 226 266 232 C269 234 273 232 276 229
        M252 212 C260 212 268 210 276 209
        M290 204 C300 202 310 202 318 200 C312 212 304 226 300 240
        """,
        x: 0,
        y: -3
      ),
      Palette.ink,
      width: 5
    )
  }
}
