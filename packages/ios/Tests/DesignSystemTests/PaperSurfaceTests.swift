import CoreGraphics
import Foundation
import Testing

@testable import DesignSystem

@Suite struct PaperSurfaceTests {
  @Test func theGrainShipsAsASmallTile() throws {
    let grain = try #require(PaperSurface.grain)
    #expect(grain.width == grain.height)
    #expect(grain.width <= 256)
    let url = try #require(PaperSurface.grainURL)
    let bytes = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    #expect(bytes <= 8 * 1024)
  }

  /// The grain only darkens the paper a little, so the ink drawn on it stays crisp.
  @Test func theGrainIsFaint() throws {
    let grain = try #require(PaperSurface.grain)
    let width = grain.width
    let height = grain.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(grain, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    #expect(drawn)
    let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    let strongest = try #require(alphas.max())
    #expect(strongest > 0)
    #expect(Double(strongest) / 255 <= 0.1)
  }
}
