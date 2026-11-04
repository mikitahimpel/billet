import CoreGraphics
import DesignSystem
import Ink
import Persistence
import Pet
import SwiftUI
import WidgetBridge
import WidgetKit

struct BedsideEntry: TimelineEntry {
  let date: Date
  let pose: UIImage?
  let note: CGImage?
}

/// The sleeping cat the app published for the chosen scene, and the latest note, for a phone
/// standing on a bedside table in StandBy.
struct BedsideProvider: TimelineProvider {
  private func entry() -> BedsideEntry {
    let storage = try? AppGroupStorage.appGroup(identifier: AppGroupStorage.billetIdentifier)
    let data = try? storage?.read(PetPose.sleeping.fileName)
    return BedsideEntry(
      date: .now,
      pose: data.flatMap(UIImage.init(data:)), note: NoteImage.loadLatest())
  }

  func placeholder(in context: Context) -> BedsideEntry {
    BedsideEntry(date: .now, pose: nil, note: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (BedsideEntry) -> Void) {
    completion(entry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BedsideEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .never))
  }
}

struct BedsideView: View {
  @Environment(\.widgetRenderingMode) private var renderingMode
  let entry: BedsideEntry

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if let pose = entry.pose {
        Image(uiImage: pose)
          .resizable()
          .scaledToFill()
          .accessibilityLabel("Your pet, asleep")
      } else {
        Text(verbatim: "billet")
          .billetType(.heading)
          .foregroundStyle(Palette.paper.color)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let note = entry.note {
        Image(decorative: NoteImage.trimmedToInk(note), scale: 1)
          .resizable()
          .scaledToFit()
          .padding(Spacing.hair)
          .frame(width: 54, height: 54)
          .background(
            renderingMode == .fullColor
              ? Palette.paper.color : Palette.paper.color.opacity(0.9),
            in: .rect(cornerRadius: Radius.paper)
          )
          .padding(Spacing.small)
          .widgetAccentable()
          .accessibilityLabel("Your partner's latest drawing")
      }
    }
    .containerBackground(for: .widget) { Palette.skyNight.color }
  }
}

/// A small widget for StandBy: the phone on a stand becomes a small house on the nightstand.
struct BedsideWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "BedsideHouse", provider: BedsideProvider()) { entry in
      BedsideView(entry: entry)
    }
    .configurationDisplayName("Bedside house")
    .description("The sleeping cat and the latest note, for StandBy.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}
