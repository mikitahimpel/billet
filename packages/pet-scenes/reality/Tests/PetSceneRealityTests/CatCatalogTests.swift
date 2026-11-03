import CoreGraphics
import Foundation
import Pet
import RealityKit
import Testing

@testable import PetSceneReality

@Suite struct CatCatalogTests {
  /// The Nooki room picks from these clips by name, and its yarn game times the pounce at 1.5 s.
  @Test func theStandardCatHasEveryNookiClip() throws {
    let clips = CatCatalog.clips(CatChoice.standard.model)
    for clip in NookiClip.allCases {
      let action = try #require(CatAction(rawValue: clip.rawValue), "\(clip)")
      #expect(clips[action] != nil, "\(clip)")
    }
    #expect(try abs(#require(clips[.pounce]).duration - 1.5) < 0.01)
    #expect(clips[.pounce]?.loops == false)
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
    for model in CatModel.allCases {
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

  /// Each detailed cat swaps its whole painted texture for a coat, eyes included, keeps its own for
  /// the coat it was made with, and plays every action.
  @MainActor @Test(arguments: [CatModel.detailed, .detailedKitten, .detailedFluffy])
  func detailedCatsWearTheirCoatTextures(model: CatModel) async throws {
    #expect(model.paintsCoatTextures)
    #expect(CatCatalog.palette(model, coat: .natural) == nil)
    #expect(CatCatalog.palette(model, coat: .cream) == nil)
    let cat = try #require(await NookiAssets.compiledCat(model))
    let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)))
    for coat in model.coats where coat != .natural {
      let texture = try #require(CatCatalog.palette(model, coat: coat), "\(model) \(coat)")
      #expect(texture.width == 1024)
      #expect(rig.paint(texture) >= 2, "\(model) \(coat): fur and eyes both take the coat")
    }
    // A move with stand-ins is one a cat may lack; every other move each made cat has.
    for action in CatAction.allCases where action.standIns.isEmpty {
      #expect(rig.info[action] != nil, "\(model) \(action)")
    }
  }

  @MainActor @Test func everyBundledCatLoadsAndRigs() async throws {
    for model in CatModel.allCases where !CatCatalog.clips(model).isEmpty {
      let cat = try #require(await NookiAssets.compiledCat(model), "\(model)")
      let rig = try #require(CatRig(model: cat, clips: CatCatalog.clips(model)), "\(model)")
      #expect(rig.info[.sleep] != nil || rig.info[.idle] != nil)
      let missing = Set(CatCatalog.clips(model).keys).subtracting(rig.info.keys)
      #expect(missing.isEmpty, "\(model) drops \(missing.map(\.rawValue).sorted())")
      if let palette = CatCatalog.palette(model, coat: .black) {
        #expect(rig.paint(palette) > 0, "\(model) has no material a coat can repaint")
      }
    }
  }

  /// realitytool drops a timeline's unchanging tail, so the last clip may end a little past it;
  /// a clip that starts past the end, or runs well past it, is not in the timeline.
  @Test func aClipMayEndInTheTimelinesDroppedTail() {
    let tail = CatClipRange(trimStart: 66.2, trimEnd: 68.4, loops: false, base: .stand)
    #expect(CatRig.fits(tail, timelineDuration: 68.2))
    #expect(!CatRig.fits(tail, timelineDuration: 66.0))
    let beyond = CatClipRange(trimStart: 60.0, trimEnd: 69.0, loops: false, base: .stand)
    #expect(!CatRig.fits(beyond, timelineDuration: 68.2))
  }
}
