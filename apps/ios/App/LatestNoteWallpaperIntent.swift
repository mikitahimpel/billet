import AppIntents
import CoreGraphics
import ImageIO
import Ink
import Labs
import Persistence
import UniformTypeIdentifiers
import WidgetBridge

/// A Shortcuts action that hands back the partner's latest note on the night sky, sized for the
/// Lock Screen. A shortcut can pass the picture to "Set Wallpaper" each morning.
struct LatestNoteWallpaperIntent: AppIntent {
  static let title: LocalizedStringResource = "Make a wallpaper from the latest note"
  static let description = IntentDescription(
    "The newest note from your partner, drawn on the night sky as a picture for your wallpaper.")
  static let openAppWhenRun = false

  enum Failure: Error, CustomLocalizedStringResourceConvertible {
    case noNote
    case notDrawn

    var localizedStringResource: LocalizedStringResource {
      switch self {
      case .noNote: "There is no note from your partner yet."
      case .notDrawn: "The wallpaper could not be drawn."
      }
    }
  }

  func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
    guard let note = NoteImage.loadLatest() else { throw Failure.noNote }
    guard let wallpaper = WallpaperImage.render(note: note),
      let data = Self.png(wallpaper)
    else { throw Failure.notDrawn }
    return .result(value: IntentFile(data: data, filename: "billet-wallpaper.png", type: .png))
  }

  private static func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
