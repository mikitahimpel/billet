import DesignSystem
import Persistence
import Surfaces
import SwiftUI
import WidgetBridge
import WidgetKit

struct ActionsEntry: TimelineEntry {
  let date: Date
  let features: WidgetFeatures
  let snapshot: WidgetSnapshot?
  let pending: [WidgetAction]
}

struct ActionsProvider: TimelineProvider {
  private func entry() -> ActionsEntry {
    ActionsEntry(
      date: .now,
      features: WidgetFeaturesStore.appGroup()?.load() ?? WidgetFeatures(),
      snapshot: WidgetSnapshotStore.appGroup()?.load(),
      pending: ActionQueue.appGroup()?.pending(at: .now) ?? [])
  }

  func placeholder(in context: Context) -> ActionsEntry {
    ActionsEntry(date: .now, features: WidgetFeatures(), snapshot: nil, pending: [])
  }

  func getSnapshot(in context: Context, completion: @escaping (ActionsEntry) -> Void) {
    completion(entry())
  }

  /// Refreshes every quarter hour, which is also when a new day's treat becomes available.
  func getTimeline(in context: Context, completion: @escaping (Timeline<ActionsEntry>) -> Void) {
    completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
  }
}

struct ActionsEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: ActionsEntry

  var body: some View {
    let surface: ActionSurface = family.isAccessory ? .lockScreen : .home
    ActionButtonsView(
      kinds: ActionButtonState.kinds(features: entry.features, surface: surface),
      snapshot: entry.snapshot, pending: entry.pending, surface: surface,
      layout: family.pictureLayout, now: entry.date, calendar: .current
    )
    .containerBackground(for: .widget) {
      if family.isAccessory { Color.clear } else { EveningBackground() }
    }
  }
}

struct ActionsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "Actions", provider: ActionsProvider()) { entry in
      ActionsEntryView(entry: entry)
    }
    .configurationDisplayName("billet buttons")
    .description("Give the treat, pet the cat, send a heart. Sent when billet next opens.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    .contentMarginsDisabled()
  }
}
