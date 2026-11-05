import UIKit
import WidgetKit

struct NookiEntry<Configuration: NookiConfiguration>: TimelineEntry {
    let date: Date
    let snapshot: NookiSnapshot
    let configuration: Configuration
    /// The newest pinned moment, downscaled: the extension has a tight memory limit.
    let momentImage: Data?
}

/// One provider for every Nooki widget: reads the shared stores once per timeline and lays out an entry for each
/// moment the picture changes on its own (WidgetTimeline). Saves elsewhere reload it through WidgetCenter.
struct NookiProvider<Configuration: NookiConfiguration>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NookiEntry<Configuration> {
        NookiEntry(date: .now, snapshot: .sample(), configuration: Configuration(), momentImage: nil)
    }

    func snapshot(for configuration: Configuration, in context: Context) async -> NookiEntry<Configuration> {
        // The widget gallery shows sample data rather than the couple's own lists and photos.
        if context.isPreview { return placeholder(in: context) }
        return Stores().entry(at: .now, configuration: configuration)
    }

    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<NookiEntry<Configuration>> {
        let stores = Stores()
        let dates = WidgetTimeline.entryDates(from: .now, activity: stores.activity, moods: stores.moods)
        return Timeline(entries: dates.map { stores.entry(at: $0, configuration: configuration) }, policy: .atEnd)
    }
}

/// The shared stores, read once for a whole timeline.
private struct Stores {
    let couple = CoupleStore().couple
    let moods = MoodStore().latest
    let activity = WidgetActivity.load()
    let us = UsStore(wallet: WalletStore())
    let moment: (preview: NookiSnapshot.MomentPreview, image: Data?)?

    init() {
        let store = MomentStore()
        moment = (store.pinned.first ?? store.moments.first).map { moment in
            let url = MomentStore.imageURL(for: moment)
            return (NookiSnapshot.MomentPreview(id: moment.id, caption: moment.caption, imageURL: url),
                    Downsample.image(at: url, maxPixels: 600)?.jpegData(compressionQuality: 0.85))
        }
    }

    func entry<C: NookiConfiguration>(at date: Date, configuration: C) -> NookiEntry<C> {
        NookiEntry(date: date,
                   snapshot: NookiSnapshot(date: date, couple: couple, moods: moods, activity: activity, us: us,
                                           listID: configuration.listID, moment: moment?.preview),
                   configuration: configuration,
                   momentImage: moment?.image)
    }
}

extension NookiSnapshot {
    /// Gallery and placeholder data: a plausible evening, nothing from the couple's real stores.
    static func sample(now: Date = .now) -> NookiSnapshot {
        let cal = Calendar.current
        return NookiSnapshot(
            date: now, viewer: "L", partner: "M", daysTogether: 127,
            next: NextEvent(title: "4 months together", icon: .init(symbol: "sparkles", tint: .sun),
                            date: cal.date(byAdding: .day, value: 18, to: now) ?? now, daysLeft: 18),
            partnerMood: MoodCheckIn(mood: .missing, date: now.addingTimeInterval(-1200)),
            myMood: nil,
            list: ListPreview(id: UUID(), title: "Groceries", icon: ListKind.groceries.icon,
                              items: [.init(id: UUID(), text: "Oat milk", author: "M", done: false),
                                      .init(id: UUID(), text: "Cat treats", author: "L", done: false),
                                      .init(id: UUID(), text: "Lemons", author: "M", done: true)],
                              openCount: 2, partnerAddedToday: false),
            planned: nil,
            idea: IdeaPreview(id: 1, title: "Blanket fort cinema", pitch: "Build a fort, pick a movie, no phones allowed inside",
                              matched: true),
            moment: nil, isPurring: false, isNight: isNight(now))
    }
}
