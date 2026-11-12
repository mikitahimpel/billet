import MomentsInterface
import MoodInterface
import WidgetInterface
import WidgetUI
import ProfileInterface
import UIKit
import UsInterface
import WidgetKit

struct OurioEntry<Configuration: OurioConfiguration>: TimelineEntry {
    let date: Date
    let snapshot: OurioSnapshot
    let configuration: Configuration
    /// The newest pinned moment, downscaled: the extension has a tight memory limit.
    let momentImage: Data?
}

/// One provider for every Ourio widget: reads the shared stores once per timeline and lays out an entry for each
/// moment the picture changes on its own (WidgetTimeline). Saves elsewhere reload it through WidgetCenter.
struct OurioProvider<Configuration: OurioConfiguration>: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> OurioEntry<Configuration> {
        OurioEntry(date: .now, snapshot: .sample(), configuration: Configuration(), momentImage: nil)
    }

    func snapshot(for configuration: Configuration, in context: Context) async -> OurioEntry<Configuration> {
        // The widget gallery shows sample data rather than the couple's own lists and photos.
        if context.isPreview { return placeholder(in: context) }
        return Stores().entry(at: .now, configuration: configuration)
    }

    func timeline(for configuration: Configuration, in context: Context) async -> Timeline<OurioEntry<Configuration>> {
        let stores = Stores()
        let dates = WidgetTimeline.entryDates(from: .now, activity: stores.activity, moods: stores.moods)
        return Timeline(entries: dates.map { stores.entry(at: $0, configuration: configuration) }, policy: .atEnd)
    }
}

/// The shared stores, read once for a whole timeline.
struct Stores {
    let couple = CoupleStore().couple
    let moods = MoodStore().latest
    let activity = WidgetActivity.load()
    let needs = CatNeedsGlance.load()
    let us = UsStore()
    let moment: (preview: OurioSnapshot.MomentPreview, image: Data?, date: Date)?

    /// The photo is decoded only for the widgets that show it: the extension's memory limit is tight.
    init(loadsPhoto: Bool = true) {
        let store = MomentStore()
        moment = (store.pinned.first ?? store.moments.first).map { moment in
            let url = MomentStore.imageURL(for: moment)
            return (OurioSnapshot.MomentPreview(id: moment.id, caption: moment.caption, imageURL: url),
                    loadsPhoto ? Downsample.image(at: url, maxPixels: 600)?.jpegData(compressionQuality: 0.85) : nil,
                    moment.date)
        }
    }

    func entry<C: OurioConfiguration>(at date: Date, configuration: C) -> OurioEntry<C> {
        OurioEntry(date: date,
                   snapshot: OurioSnapshot(date: date, couple: couple, moods: moods, activity: activity, us: us,
                                           listID: configuration.listID, moment: moment?.preview),
                   configuration: configuration,
                   momentImage: moment?.image)
    }
}

/// The family widgets: no configuration, one timeline of a few entries a day (FamilyTimeline).
struct FamilyProvider: TimelineProvider {
    var loadsPhoto = false

    func placeholder(in context: Context) -> FamilyEntry {
        FamilyEntry(date: .now, snapshot: .sample(), facts: .sample(), momentImage: nil, momentDate: nil, want: .food)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: .now, stores: Stores(loadsPhoto: loadsPhoto),
                                                                        facts: .load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyEntry>) -> Void) {
        let stores = Stores(loadsPhoto: loadsPhoto)
        let facts = WidgetFacts.load()
        let dates = FamilyTimeline.entryDates(from: .now, activity: stores.activity, moods: stores.moods,
                                              drawing: facts.drawing)
        completion(Timeline(entries: dates.map { entry(at: $0, stores: stores, facts: facts) }, policy: .atEnd))
    }

    private func entry(at date: Date, stores: Stores, facts: WidgetFacts) -> FamilyEntry {
        let configured: OurioEntry<ModuleConfiguration> = stores.entry(at: date, configuration: ModuleConfiguration())
        let want = stores.needs?.want(at: date, asleep: configured.snapshot.isNight, fedAt: stores.activity.lastFed,
                                      pettedAt: stores.activity.lastPet)
        return FamilyEntry(date: date, snapshot: configured.snapshot, facts: facts, momentImage: configured.momentImage,
                           momentDate: stores.moment?.date, want: want)
    }
}
