import Persistence
import Pet
import SwiftUI
import UIKit
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  var body: some Widget {
    PetPoseWidget()
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
    .supportedFamilies([.systemSmall])
  }
}
