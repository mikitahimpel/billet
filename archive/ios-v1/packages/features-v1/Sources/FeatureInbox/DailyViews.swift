import CoreGraphics
import DesignSystem
import Ink
import SwiftUI
import Wire

/// One drawing of the day on its sheet of paper, or a blank sheet saying why it is blank.
public struct DailyPaper: View {
  private let strokes: [Stroke]?
  private let blank: String
  private let side: Int

  @State private var image: CGImage?

  /// - Parameters:
  ///   - strokes: The drawing, or `nil` for a blank sheet.
  ///   - blank: What a blank sheet says.
  ///   - side: Pixel side of the rendered picture.
  public init(strokes: [Stroke]?, blank: String, side: Int = 360) {
    self.strokes = strokes
    self.blank = blank
    self.side = side
  }

  public var body: some View {
    RoundedRectangle(cornerRadius: Radius.paper)
      .fill(strokes == nil ? Palette.paperTurned.color : Palette.paper.color)
      .overlay {
        if let image {
          Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
        } else if strokes == nil {
          Text(blank)
            .billetType(.caption)
            .foregroundStyle(Palette.ink.color.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(Spacing.small)
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: Radius.paper))
      .shadow(color: Palette.pageDeep.color.opacity(0.5), radius: 3, x: 1, y: 2)
      .task(id: strokes) {
        guard let strokes else {
          image = nil
          return
        }
        let side = side
        image = await Task.detached { NoteImage.cgImage(of: strokes, side: side) }.value
      }
      .accessibilityLabel(Text(strokes == nil ? blank : "A drawing"))
  }
}

/// What a partner's sheet says while it is blank.
public enum DailyBlank {
  public static func theirs(_ entry: DailyEntry) -> String {
    entry.theirsDrawn ? "Drawn, and waiting for yours" : "Not drawn yet"
  }

  public static let mine = "You didn't draw this one"
}

/// The archive of the drawing of the day: each day's prompt, with both drawings side by side.
struct DailyArchiveList: View {
  let entries: [DailyEntry]

  var body: some View {
    if entries.isEmpty {
      EmptyWire(
        title: "No daily drawings yet",
        message: "Each day brings one prompt for you both. Your drawings of it will gather here.")
    } else {
      LazyVStack(spacing: 0) {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
          if index > 0 { ListDivider() }
          DailyArchiveRow(entry: entry)
        }
      }
      .card()
    }
  }
}

private struct DailyArchiveRow: View {
  let entry: DailyEntry

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.small) {
      HStack(alignment: .firstTextBaseline) {
        Text(entry.prompt.text)
          .billetType(.label)
          .foregroundStyle(Palette.paper.color)
        Spacer(minLength: Spacing.small)
        Text(DailyDay.title(entry.day))
          .billetType(.caption)
          .foregroundStyle(Palette.muted.color)
      }
      HStack(spacing: Spacing.small) {
        labelled("You", DailyPaper(strokes: entry.mine, blank: DailyBlank.mine, side: 240))
        labelled(
          "Them", DailyPaper(strokes: entry.theirs, blank: DailyBlank.theirs(entry), side: 240))
      }
    }
    .padding(Spacing.medium)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("dailyArchiveRow")
  }

  private func labelled(_ title: String, _ paper: DailyPaper) -> some View {
    VStack(spacing: Spacing.hair) {
      paper
      Text(title)
        .billetType(.caption)
        .foregroundStyle(Palette.muted.color)
    }
    .frame(maxWidth: .infinity)
  }
}

/// A calendar day as the archive shows it: "4 Nov".
enum DailyDay {
  static func title(_ day: String) -> String {
    let parser = DateFormatter()
    parser.calendar = Calendar(identifier: .gregorian)
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd"
    guard let date = parser.date(from: day) else { return day }
    return date.formatted(.dateTime.day().month(.abbreviated))
  }
}
