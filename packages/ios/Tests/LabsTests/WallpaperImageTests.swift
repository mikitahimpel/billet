import CoreGraphics
import Foundation
import Testing
import Wire

@testable import Labs

@Suite struct WallpaperImageTests {
  private let strokes = [
    Stroke(
      color: "#A5442B", width: 0.05,
      points: [Point(x: 0.1, y: 0.1), Point(x: 0.9, y: 0.9), Point(x: 0.1, y: 0.9)])
  ]

  private func bytes(_ image: CGImage) -> Data {
    image.dataProvider?.data as Data? ?? Data()
  }

  @Test func theNoteSitsBelowTheClockAndInsideTheScreen() {
    let size = WallpaperImage.size
    let rect = WallpaperImage.noteRect(in: size)
    #expect(rect.minY >= size.height * 0.25)
    #expect(rect.minX >= 0 && rect.maxX <= size.width)
    #expect(rect.maxY <= size.height * 0.9)
    #expect(rect.width == rect.height)
  }

  @Test func theImageHasThePhonesSize() throws {
    let image = try #require(WallpaperImage.render(strokes: strokes))
    #expect(image.width == 1170 && image.height == 2532)
  }

  @Test func aNoteChangesThePicture() throws {
    let small = CGSize(width: 234, height: 506)
    let sky = try #require(WallpaperImage.render(note: nil, size: small))
    let withNote = try #require(WallpaperImage.render(strokes: strokes, size: small))
    #expect(bytes(sky) != bytes(withNote))
    #expect(!bytes(sky).isEmpty)
  }

  @Test func theSameNoteGivesTheSamePicture() throws {
    let small = CGSize(width: 234, height: 506)
    let one = try #require(WallpaperImage.render(strokes: strokes, size: small))
    let two = try #require(WallpaperImage.render(strokes: strokes, size: small))
    #expect(bytes(one) == bytes(two))
  }

  @Test func theSkyIsOpaque() throws {
    let image = try #require(WallpaperImage.render(note: nil, size: CGSize(width: 64, height: 128)))
    let data = bytes(image)
    #expect(stride(from: 3, to: data.count, by: 4).allSatisfy { data[$0] == 255 })
  }
}
