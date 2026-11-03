import CoreGraphics
import DesignSystem
import Persistence
import Pet
import Surfaces
import SwiftUI
import WidgetBridge
import WidgetKit

struct PictureEntry: TimelineEntry {
  let date: Date
  let choice: PicturePlan.Choice
  let context: PictureContext
}

/// Reads the flags, the app's snapshot and the latest drawing, and plans which picture shows when.
struct PictureProvider: TimelineProvider {
  private struct Loaded {
    let inputs: PicturePlan.Inputs
    let drawing: CGImage?
    let pose: Data?
    let awakePose: Data?
  }

  private func load() -> Loaded {
    let features = WidgetFeaturesStore.appGroup()?.load() ?? WidgetFeatures()
    let snapshot = WidgetSnapshotStore.appGroup()?.load()
    let drawing = LatestNoteView.loadLatest()
    let storage = try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier)
    let pose = (try? storage?.read(PetPose.sleeping.fileName)) ?? nil
    let awakePose = (try? storage?.read(PetPose.proud.fileName)) ?? nil
    let inputs = PicturePlan.Inputs(
      features: features, snapshot: snapshot, hasDrawing: drawing != nil, calendar: .current)
    return Loaded(inputs: inputs, drawing: drawing, pose: pose, awakePose: awakePose)
  }

  private func entry(_ loaded: Loaded, at date: Date) -> PictureEntry {
    PictureEntry(
      date: date,
      choice: PicturePlan.choice(loaded.inputs, at: date),
      context: PictureContext(
        snapshot: loaded.inputs.snapshot, drawing: loaded.drawing, catPose: loaded.pose,
        catAwakePose: loaded.awakePose, now: date, calendar: loaded.inputs.calendar))
  }

  func placeholder(in context: Context) -> PictureEntry {
    PictureEntry(
      date: .now, choice: .nothingYet,
      context: PictureContext(snapshot: nil, drawing: nil, now: .now, calendar: .current))
  }

  func getSnapshot(in context: Context, completion: @escaping (PictureEntry) -> Void) {
    completion(entry(load(), at: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<PictureEntry>) -> Void) {
    let loaded = load()
    let dates = PicturePlan.dates(loaded.inputs, from: .now)
    let entries = dates.map { entry(loaded, at: $0) }
    completion(Timeline(entries: entries, policy: .after(dates.last ?? .now)))
  }
}

struct PictureEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: PictureEntry

  var body: some View {
    PictureView(entry.choice, context: entry.context, layout: family.pictureLayout)
      .containerBackground(for: .widget) {
        if family.isAccessory {
          Color.clear
        } else {
          PictureBackground(entry.choice, context: entry.context).savedEveningGround()
        }
      }
  }
}

extension WidgetFamily {
  var pictureLayout: PictureLayout {
    switch self {
    case .accessoryInline: .inline
    case .accessoryCircular: .circular
    case .accessoryRectangular: .rectangular
    case .systemSmall: .small
    case .systemMedium, .systemLarge, .systemExtraLarge: .roomy
    @unknown default: .roomy
    }
  }

  var isAccessory: Bool {
    switch self {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
    case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: false
    @unknown default: false
    }
  }
}

struct PicturesWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Pictures", provider: PictureProvider()) { entry in
      PictureEntryView(entry: entry)
    }
    .configurationDisplayName("billet pictures")
    .description("Your drawings, the cat and the house. Choose what shows in billet Settings.")
    .supportedFamilies([
      .systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular,
      .accessoryInline,
    ])
    .contentMarginsDisabled()
  }
}
