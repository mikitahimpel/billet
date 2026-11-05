import SwiftUI
import Wire

/// The soft, bright wallpapers behind the drawing. Each is one of the note papers, so the partner's widget can show
/// the drawing on the same wallpaper.
enum LockWallpaper: String, CaseIterable, Identifiable {
    case blush, butter, sage, sky, cream

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var paper: PaperColor {
        switch self {
        case .blush: .blush
        case .butter: .butter
        case .sage: .sage
        case .sky: .sky
        case .cream: .cream
        }
    }

    /// Top-left to bottom-right, light enough that every ink reads on it.
    var colors: [Color] {
        switch self {
        case .blush: [Color(hex: 0xFFD3DF), Color(hex: 0xFFB7C9), Color(hex: 0xE9B5F5)]
        case .butter: [Color(hex: 0xFFF1C2), Color(hex: 0xFFD98C), Color(hex: 0xFFB98A)]
        case .sage: [Color(hex: 0xDDF2D8), Color(hex: 0xB5DDB8), Color(hex: 0x9CCFC4)]
        case .sky: [Color(hex: 0xD8ECFF), Color(hex: 0xB0D4FF), Color(hex: 0xC7B9FF)]
        case .cream: [Color(hex: 0xFFF8EC), Color(hex: 0xF7E6CF), Color(hex: 0xF0D3B8)]
        }
    }
}

/// The wallpaper, or the couple's photo when they picked one, filling whatever it is laid behind.
struct LockWallpaperView: View {
    let wallpaper: LockWallpaper
    var photo: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: wallpaper.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            // A soft bloom, so the wallpaper has depth like the system ones.
            RadialGradient(colors: [.white.opacity(0.55), .clear], center: .init(x: 0.3, y: 0.25),
                           startRadius: 0, endRadius: 420)
            if let photo {
                Color.clear.overlay {
                    Image(uiImage: photo).resizable().scaledToFill()
                }
                .clipped()
            }
        }
    }
}
