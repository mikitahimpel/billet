import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct CatCatalogTests {
  @Test func mochiKeepsItsOldTrims() throws {
    let sleep = try #require(CatCatalog.mochiClips[.sleep])
    #expect(sleep.trimStart == 10)
    #expect(sleep.trimEnd == 16)
    #expect(sleep.base == .sleep)
    #expect(CatCatalog.mochiClips.count == NookiClip.allCases.count)
  }

  @Test func unknownAndEmptyClipsAreSkipped() {
    let table: [String: CatClipRange] = [
      "sit": CatClipRange(trimStart: 1, trimEnd: 3, loops: true),
      "dance": CatClipRange(trimStart: 3, trimEnd: 4, loops: false),
      "yawn": CatClipRange(trimStart: 4, trimEnd: 4, loops: false),
    ]
    let decoded = CatCatalog.decoded(table)
    #expect(Set(decoded.keys) == [.sit])
    #expect(decoded[.sit]?.base == .sit)
  }

  @Test func everyBundledCatHasItsTableAndCoats() {
    for model in CatModel.allCases where model != .mochi {
      let clips = CatCatalog.clips(model)
      guard !clips.isEmpty else { continue }
      #expect(clips[.idle] != nil, "\(model)")
      #expect(clips[.sleep] != nil, "\(model)")
      for coat in model.coats where coat != .natural {
        #expect(CatCatalog.palette(model, coat: coat) != nil, "\(model) \(coat)")
      }
    }
  }

  @Test func aCoatRepaintsOnlyItsSwatches() throws {
    let size = 128
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
      CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 1, green: 0, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let blank = try #require(context.makeImage())
    let colours = try #require(CatCatalog.colours(.black, keepsWhiteBelly: false))
    let painted = try #require(CatCatalog.repaint(blank, colours))
    let pixels = try #require(painted.dataProvider?.data as Data?)
    func pixel(swatch: Int) -> [UInt8] {
      let x = (swatch % 4) * 32 + 16
      let y = (swatch / 4) * 32 + 16
      let at = y * painted.bytesPerRow + x * 4
      return Array(pixels[at..<at + 3])
    }
    #expect(pixel(swatch: 0) == [0x2A, 0x27, 0x2C])
    #expect(pixel(swatch: 7) == [0x3A, 0x36, 0x3D])
    #expect(pixel(swatch: 4) == [0xFF, 0x00, 0xFF])
    #expect(CatCatalog.colours(.natural, keepsWhiteBelly: false) == nil)
    #expect(CatCatalog.colours(.black, keepsWhiteBelly: true)?[.belly] == 0xF7F5F2)
  }

  @MainActor @Test func everyBundledCatLoadsAndRigs() async throws {
    for model in CatModel.allCases where model != .mochi && !CatCatalog.clips(model).isEmpty {
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      #expect(rig.info[.sleep] != nil || rig.info[.idle] != nil)
      if let palette = CatCatalog.palette(model, coat: .black) {
        #expect(rig.paint(palette) > 0, "\(model) has no material a coat can repaint")
      }
    }
  }
}
