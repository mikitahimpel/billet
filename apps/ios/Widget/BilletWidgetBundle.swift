import SwiftUI
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  var body: some Widget {
    PlaceholderWidget()
  }
}

struct PlaceholderEntry: TimelineEntry {
  let date: Date
}

struct PlaceholderProvider: TimelineProvider {
  func placeholder(in context: Context) -> PlaceholderEntry {
    PlaceholderEntry(date: .now)
  }

  func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
    completion(PlaceholderEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void)
  {
    completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
  }
}

struct PlaceholderWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PlaceholderWidget", provider: PlaceholderProvider()) { _ in
      Text("billet")
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .supportedFamilies([.systemSmall])
  }
}
