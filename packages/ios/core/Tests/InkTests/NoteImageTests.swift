import CoreGraphics
import Ink
import Testing
import Wire

@Suite("NoteImage")
struct NoteImageTests {
  @Test func trimmingCutsAWideDrawingToItsInk() throws {
    let wide = Stroke(
      color: "#000000", width: 0.02, points: [Point(x: 0.1, y: 0.5), Point(x: 0.9, y: 0.5)])
    let image = try #require(NoteImage.cgImage(of: [wide]))
    let trimmed = NoteImage.trimmedToInk(image)
    #expect(trimmed.width > trimmed.height * 4)
    #expect(trimmed.height < image.height / 4)
  }
}
