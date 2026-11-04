import CoreGraphics
import DesignSystem
import Persistence
import Pet
import Surfaces
import SwiftUI
import UIKit
import WidgetBridge
import WidgetKit

@main
struct BilletWidgetBundle: WidgetBundle {
  init() {
    // Without the bundled faces the widget falls back to the system font, which still reads fine.
    try? BilletFonts.register()
  }

  var body: some Widget {
    PicturesWidget()
    ActionsWidget()
    PetCatControl()
    SendHeartControl()
    OpenCanvasControl()
    CatTripActivity()
    LatestNoteWidget()
    PetPoseWidget()
    BedsideWidget()
  }
}

struct LatestNoteEntry: TimelineEntry {
  let date: Date
  let image: CGImage?
  /// The cat in the corner, once the app has published the pair.
  let cat: NoteCat?
}

/// Reads the latest drawing, and for the cat the app's snapshot, its stills and the last care.
struct LatestNoteProvider: TimelineProvider {
  /// How often the entries step, so the partner's "5 min ago" and the cat's pose keep up.
  private static let step: TimeInterval = 15 * 60
  private static let horizon: TimeInterval = 2 * 60 * 60

  private struct Loaded {
    let image: CGImage?
    let snapshot: WidgetSnapshot?
    let sleepingPose: Data?
    let awakePose: Data?
    let lastCare: CatCareRecord?
  }

  private func load() -> Loaded {
    let storage = try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier)
    return Loaded(
      image: LatestNoteView.loadLatest(),
      snapshot: WidgetSnapshotStore.appGroup()?.load(),
      sleepingPose: (try? storage?.read(PetPose.sleeping.fileName)) ?? nil,
      awakePose: (try? storage?.read(PetPose.proud.fileName)) ?? nil,
      lastCare: CatCareStore.appGroup()?.load())
  }

  private func entry(_ loaded: Loaded, at date: Date) -> LatestNoteEntry {
    LatestNoteEntry(
      date: date, image: loaded.image,
      cat: loaded.snapshot.map {
        NoteCat(
          snapshot: $0, sleepingPose: loaded.sleepingPose, awakePose: loaded.awakePose,
          lastCare: loaded.lastCare, now: date, calendar: .current)
      })
  }

  func placeholder(in context: Context) -> LatestNoteEntry {
    LatestNoteEntry(date: .now, image: nil, cat: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (LatestNoteEntry) -> Void) {
    completion(entry(load(), at: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<LatestNoteEntry>) -> Void) {
    let loaded = load()
    let now = Date.now
    var dates = stride(from: 0, to: Self.horizon, by: Self.step).map {
      now.addingTimeInterval($0)
    }
    if let until = CatCareRequest.cooling(last: loaded.lastCare, now: now) {
      dates.append(until)
    }
    dates.sort()
    let end = now.addingTimeInterval(Self.horizon)
    completion(Timeline(entries: dates.map { entry(loaded, at: $0) }, policy: .after(end)))
  }
}

struct LatestNoteEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: LatestNoteEntry

  var body: some View {
    switch family {
    case .accessoryRectangular:
      LockNoteRectangular(image: entry.image)
        .containerBackground(.clear, for: .widget)
    case .accessoryCircular:
      LockNoteCircular(image: entry.image)
        .containerBackground(.clear, for: .widget)
    default:
      NoteCatView(image: entry.image, cat: entry.cat)
        .containerBackground(for: .widget) { PaperSurface() }
    }
  }
}

struct LatestNoteWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "LatestNote", provider: LatestNoteProvider()) { entry in
      LatestNoteEntryView(entry: entry)
    }
    .configurationDisplayName("Latest note")
    .description("Your partner's latest drawing, with the cat in the corner.")
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
      .containerBackground(for: .widget) { EveningBackground().savedEveningGround() }
    }
    .configurationDisplayName("Your pet")
    .description("Your pet, asleep at home.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

extension View {
  /// The ground chosen in Labs, read from the shared container, so the widgets match the app.
  func savedEveningGround() -> some View {
    environment(\.eveningGround, WidgetFeaturesStore.appGroup()?.loadEveningGround() ?? .standard)
  }
}
