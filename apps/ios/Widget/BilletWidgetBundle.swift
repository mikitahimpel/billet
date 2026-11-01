import CoreGraphics
import DesignSystem
import Persistence
import Pet
import Surfaces
import SwiftUI
import UIKit
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  init() {
    // Without the bundled faces the widget falls back to the system font, which still reads fine.
    try? BilletFonts.register()
  }

  var body: some Widget {
    PicturesWidget()
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

  var body: some View {
    switch family {
    case .accessoryRectangular:
      LockNoteRectangular(image: image)
        .containerBackground(.clear, for: .widget)
    case .accessoryCircular:
      LockNoteCircular(image: image)
        .containerBackground(.clear, for: .widget)
    default:
      LatestNoteView(image: image)
        .containerBackground(for: .widget) { EveningBackground() }
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
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular,
    ])
    .contentMarginsDisabled()
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
          Text(verbatim: "billet")
            .billetType(.heading)
            .foregroundStyle(Palette.paper.color)
        }
      }
      .containerBackground(for: .widget) { EveningBackground() }
    }
    .configurationDisplayName("Your pet")
    .description("Your pet, asleep at home.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}
