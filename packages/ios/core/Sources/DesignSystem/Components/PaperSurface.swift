import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// Plain warm paper with a faint grain, filling whatever it is given edge to edge: one surface,
/// no frame. The grain is a 96 px tile (`Resources/Paper/paper-grain.png`, made by
/// `scripts/make-paper-grain.py`) that only ever darkens the paper a little.
public struct PaperSurface: View {
  public init() {}

  public var body: some View {
    ZStack {
      Palette.paper.color
      if let grain = Self.grain {
        Image(decorative: grain, scale: 1)
          .resizable(resizingMode: .tile)
      }
    }
  }

  /// Where the grain tile ships.
  nonisolated static var grainURL: URL? {
    Bundle.module.url(forResource: "paper-grain", withExtension: "png", subdirectory: "Paper")
  }

  /// The grain tile, read once. `nil` if the bundle lacks it, which leaves plain paper.
  public nonisolated static let grain: CGImage? = {
    guard let url = grainURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }()
}
