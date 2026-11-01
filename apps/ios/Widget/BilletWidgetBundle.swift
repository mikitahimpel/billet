import CoreGraphics
import Persistence
import Pet
import Surfaces
import SwiftUI
import UIKit
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  var body: some Widget {
    LatestNoteWidget()
    PetPoseWidget()
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

struct PetPoseEntry: TimelineEntry {
  let date: Date
  let image: UIImage?
}

/// Reads the pose the app published for the chosen scene. The app reloads timelines when the
/// choice changes, so one entry with no refresh is enough.
struct PetPoseProvider: TimelineProvider {
  private func entry() -> PetPoseEntry {
    let storage = try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier)
    let data = try? storage?.read(PetPose.sleeping.fileName)
    return PetPoseEntry(date: .now, image: data.flatMap(UIImage.init(data:)))
  }

  func placeholder(in context: Context) -> PetPoseEntry {
    PetPoseEntry(date: .now, image: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (PetPoseEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PetPoseEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .never))
  }
}

struct PetPoseWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "PetPoseWidget", provider: PetPoseProvider()) { entry in
      Group {
        if let image = entry.image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .accessibilityLabel("Your pet, asleep")
        } else {
          Text("billet")
        }
      }
      .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Your pet")
    .description("Your pet, asleep at home.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
