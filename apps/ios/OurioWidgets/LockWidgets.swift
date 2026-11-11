import Design
import MoodInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import WidgetKit

// Lock Screen: one glyph or two short lines, drawn for the system's vibrant tint, so no colour carries meaning.

struct UsLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.lock.us", provider: FamilyProvider()) { entry in
            FamilyBody { UsLockView(entry: entry, family: $0) }.lockGround().widgetURL(DeepLink.calendar.url)
        }
        .configurationDisplayName("Days together")
        .description("Your days together and the next date.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StreakLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.lock.streak", provider: FamilyProvider()) { entry in
            FamilyBody { StreakLockView(entry: entry, family: $0) }.lockGround().widgetURL(DeepLink.us.url)
        }
        .configurationDisplayName("Streak")
        .description("Your streak and how far the next milestone is.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CatLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.lock.cat", provider: FamilyProvider()) { entry in
            FamilyBody { CatLockView(entry: entry, family: $0) }.lockGround().widgetURL(DeepLink.room.url)
        }
        .configurationDisplayName("Mochi")
        .description("How Mochi is right now.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct PartnerLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.lock.partner", provider: FamilyProvider()) { entry in
            FamilyBody { PartnerLockView(entry: entry, family: $0) }.lockGround().widgetURL(DeepLink.inbox.url)
        }
        .configurationDisplayName("Your partner")
        .description("How your partner is, or that they drew you something.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
