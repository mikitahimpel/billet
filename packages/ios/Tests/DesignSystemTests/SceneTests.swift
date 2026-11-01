import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import DesignSystem

/// Renders a view to pixels. `BILLET_SNAPSHOT_DIR` keeps a PNG for review.
@MainActor
func render(_ view: some View, named name: String, scale: CGFloat = 2) throws -> CGImage {
  let renderer = ImageRenderer(content: view)
  renderer.scale = scale
  let image = try #require(renderer.cgImage)
  if let directory = ProcessInfo.processInfo.environment["BILLET_SNAPSHOT_DIR"] {
    let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
    let target = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    )
    CGImageDestinationAddImage(target, image, nil)
    #expect(CGImageDestinationFinalize(target))
  }
  return image
}

/// How many distinct colours the image holds, on a coarse sample.
func distinctColors(in image: CGImage) -> Int {
  let width = 200
  let height = max(1, width * image.height / image.width)
  var pixels = [UInt8](repeating: 0, count: width * height * 4)
  pixels.withUnsafeMutableBytes { buffer in
    let context = CGContext(
      data: buffer.baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  }
  var seen = Set<UInt32>()
  for index in stride(from: 0, to: pixels.count, by: 4) {
    let key =
      UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
    seen.insert(key)
  }
  return seen.count
}

func sampleNote() -> some View {
  SceneCanvas(SampleDrawing.art)
}

@Suite @MainActor struct SceneTests {
  init() throws {
    try BilletFonts.register()
  }

  @Test func stageSetIsFixedAtFive() {
    #expect(HouseStage.allCases.count == 5)
  }

  @Test(
    arguments: [
      (0, HouseStage.lit), (6, .lit),
      (7, .garden), (20, .garden),
      (21, .tree), (29, .tree),
      (30, .chimney), (47, .chimney), (59, .chimney),
      (60, .newRoom), (10_000, .newRoom),
      (-1, .lit),
    ])
  func streakPicksStage(streak: Int, stage: HouseStage) {
    #expect(HouseStage(streak: streak) == stage)
  }

  @Test func everyStageAddsMarks() {
    let counts = HouseStage.allCases.map { HouseArt.art(for: $0).marks.count }
    for (earlier, later) in zip(counts, counts.dropFirst()) {
      #expect(later != earlier)
    }
  }

  @Test func theRoomIsItsOwnComposition() {
    #expect(RoomArt.art.marks.count < HouseArt.art(for: .lit).marks.count / 3)
    #expect(RoomArt.size != HouseArt.size)
  }

  @Test(arguments: HouseStage.allCases)
  func houseStageRenders(stage: HouseStage) throws {
    let view = ScenePanel {
      HouseScene(streak: stage == .chimney ? 47 : stage.firstDay) { sampleNote() }
    }
    .frame(width: 1030, height: 704)
    let image = try render(view, named: "house-\(stage)", scale: 1)
    #expect(image.width == 1030)
    #expect(distinctColors(in: image) > 200)
  }

  @Test func roomRenders() throws {
    let view = RoomScene(name: "Mira", streak: 47) { sampleNote() }
      .frame(width: 338, height: 158)
    let image = try render(view, named: "room-medium-widget", scale: 3)
    #expect(distinctColors(in: image) > 100)
  }

  @Test func componentsRender() throws {
    let image = try render(ComponentGallery(), named: "components")
    #expect(distinctColors(in: image) > 20)
  }
}

@Suite @MainActor struct TypeTests {
  init() throws {
    try BilletFonts.register()
  }

  @Test func bundledFacesResolve() {
    for family in [BilletFonts.groteskFamily, BilletFonts.monoFamily] {
      let font = CTFontCreateWithName(family as CFString, 20, nil)
      #expect(CTFontCopyFamilyName(font) as String == family)
    }
  }

  @Test func licencesShipBesideTheFonts() throws {
    for name in ["OFL-SchibstedGrotesk", "OFL-DMMono"] {
      let url = fontsDirectory.appendingPathComponent("\(name).txt")
      let text = try String(contentsOf: url, encoding: .utf8)
      #expect(text.contains("SIL Open Font License"))
    }
  }

  @Test func theLadderStepsUp() {
    let sizes = [BilletType.caption, .label, .body, .heading, .title, .display].map(\.size)
    for (smaller, larger) in zip(sizes, sizes.dropFirst()) {
      #expect(larger > smaller)
      #expect(larger / smaller <= 1.45)
    }
  }

  @Test func heavyDiffersFromRegularSoTheVariableAxisIsLive() throws {
    func inkedWidth(_ weight: Font.Weight) throws -> Int {
      let view = Text(verbatim: "A little house for two")
        .font(.custom(BilletFonts.groteskFamily, fixedSize: 40).weight(weight))
        .fixedSize()
      return try #require(ImageRenderer(content: view).cgImage).width
    }
    #expect(try inkedWidth(.heavy) > inkedWidth(.regular))
  }
}

let fontsDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("Sources/DesignSystem/Resources/Fonts")
