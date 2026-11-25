import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes the frames of a run as an H.264 movie and keeps some of them for a contact sheet.
final class Recorder {
  let size: CGSize
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let fps: Int32
  private var frame: Int64 = 0

  init(url: URL, size: CGSize, fps: Int32 = 60) throws {
    try? FileManager.default.removeItem(at: url)
    self.size = size
    self.fps = fps
    writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width),
        AVVideoHeightKey: Int(size.height),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
      ])
    adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(size.width),
        kCVPixelBufferHeightKey as String: Int(size.height),
      ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
  }

  /// One frame, drawn by `draw` into a context with its origin bottom left.
  func add(_ draw: (CGContext) -> Void) {
    guard let pool = adaptor.pixelBufferPool else { return }
    var made: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
    guard let buffer = made else { return }
    CVPixelBufferLockBaseAddress(buffer, [])
    if let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
    {
      draw(context)
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    while !input.isReadyForMoreMediaData { usleep(1000) }
    adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: fps))
    frame += 1
  }

  func finish() async {
    input.markAsFinished()
    await writer.finishWriting()
  }
}

enum Picture {
  static func context(_ size: CGSize) -> CGContext {
    CGContext(
      data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
  }

  static func write(_ image: CGImage, to url: URL) {
    guard
      let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(out, image, nil)
    CGImageDestinationFinalize(out)
  }

  static func text(_ string: String, at point: CGPoint, size: CGFloat = 13, in context: CGContext,
                   color: CGColor = CGColor(gray: 0.15, alpha: 1)) {
    let font = CTFontCreateWithName("Menlo" as CFString, size, nil)
    let attributed = NSAttributedString(
      string: string,
      attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
      ])
    context.textPosition = point
    CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
  }

  /// `tiles` in rows of `columns`, each `tile` in size.
  static func sheet(_ tiles: [CGImage], columns: Int, tile: CGSize) -> CGImage? {
    guard !tiles.isEmpty else { return nil }
    let rows = (tiles.count + columns - 1) / columns
    let context = context(CGSize(width: tile.width * CGFloat(columns), height: tile.height * CGFloat(rows)))
    for (i, image) in tiles.enumerated() {
      let row = i / columns, column = i % columns
      context.draw(
        image,
        in: CGRect(
          x: CGFloat(column) * tile.width, y: CGFloat(rows - 1 - row) * tile.height, width: tile.width,
          height: tile.height))
    }
    return context.makeImage()
  }
}
