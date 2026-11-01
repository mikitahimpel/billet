import CoreGraphics
import Surfaces
import SwiftUI
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  var body: some Widget {
    LatestNoteWidget()
  }
}

struct LatestNoteEntry: TimelineEntry {
  let date: Date
  let image: CGImage?
}

struct LatestNoteProvider: TimelineProvider {
  func placeholder(in context: Context) -> LatestNoteEntry {
    LatestNoteEntry(date: .now, image: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (LatestNoteEntry) -> Void) {
    completion(LatestNoteEntry(date: .now, image: LatestNoteView.loadLatest()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LatestNoteEntry>) -> Void) {
    let entry = LatestNoteEntry(date: .now, image: LatestNoteView.loadLatest())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

struct LatestNoteEntryView: View {
  @Environment(\.widgetFamily) private var family
  let image: CGImage?

  private var caption: String { image == nil ? "No notes yet" : "New note" }

  var body: some View {
    switch family {
    case .accessoryRectangular:
      HStack {
        NoteSilhouette(image: image)
        Text(caption)
          .font(.headline)
      }
      .widgetAccentable()
      .containerBackground(.clear, for: .widget)
    case .accessoryCircular:
      VStack(spacing: 1) {
        NoteSilhouette(image: image)
        Text(caption)
          .font(.system(size: 9))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(6)
      .widgetAccentable()
      .containerBackground(.clear, for: .widget)
    default:
      LatestNoteView(image: image)
        .containerBackground(LatestNoteView.paper, for: .widget)
    }
  }
}

struct LatestNoteWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LatestNote", provider: LatestNoteProvider()) { entry in
      LatestNoteEntryView(image: entry.image)
    }
    .configurationDisplayName("Latest note")
    .description("Your partner's latest drawing.")
    .supportedFamilies([.systemMedium, .accessoryRectangular, .accessoryCircular])
  }
}
