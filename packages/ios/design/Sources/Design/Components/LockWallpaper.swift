import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

/// The warm, deep wallpapers behind a drawing. Each is one of the note papers, so the partner's
/// widget can show the drawing on the same wallpaper.
public enum LockWallpaper: String, CaseIterable, Identifiable, Sendable {
  case blush, butter, sage, sky, cream

  public var id: String { rawValue }

  public var title: String { rawValue.capitalized }

  /// Top-left to bottom-right. Deep warm dusks: inks are drawn in their light "on dark" colours and
  /// the clock is white, so every stop has to stay dark enough for both (WCAG 4.5:1 for white,
  /// checked in DrawingWidgetTests).
  public var stops: [UInt32] {
    switch self {
    case .blush: [0x5C3426, 0x7A4530, 0x82474F]
    case .butter: [0x5E4018, 0x7D5420, 0x80452A]
    case .sage: [0x2F4A38, 0x3B5C45, 0x2F5753]
    case .sky: [0x263F5E, 0x30507A, 0x44406E]
    case .cream: [0x5A4634, 0x6E563F, 0x6B4A3A]
    }
  }

  public var colors: [Color] { stops.map { Color(hex: $0) } }
}

/// The wallpaper, or the couple's photo when they picked one, filling whatever it is laid behind.
public struct LockWallpaperView: View {
  public let wallpaper: LockWallpaper
  #if canImport(UIKit)
    public var photo: UIImage?

    public init(wallpaper: LockWallpaper, photo: UIImage? = nil) {
      self.wallpaper = wallpaper
      self.photo = photo
    }
  #else
    public init(wallpaper: LockWallpaper) {
      self.wallpaper = wallpaper
    }
  #endif

  public var body: some View {
    ZStack {
      LinearGradient(
        colors: wallpaper.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
      // A faint honey glow, so the wallpaper has depth like the system ones without lifting any
      // stop.
      RadialGradient(
        colors: [Color.honey.opacity(0.14), .clear], center: .init(x: 0.3, y: 0.25),
        startRadius: 0, endRadius: 420)
      #if canImport(UIKit)
        if let photo {
          Color.clear.overlay {
            Image(uiImage: photo).resizable().scaledToFill()
          }
          .clipped()
          // A photo can be any brightness; the scrim keeps the white clock and the inks readable
          // on it.
          LinearGradient(
            colors: [.black.opacity(0.5), .black.opacity(0.3), .black.opacity(0.45)],
            startPoint: .top, endPoint: .bottom)
        }
      #endif
    }
  }
}
