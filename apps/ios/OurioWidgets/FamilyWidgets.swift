import Design
import DrawInterface
import MoodInterface
import Pet
import ProfileInterface
import WidgetInterface
import WidgetUI
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen family, as WidgetKit declares it; the views are in FamilyViews.swift.

struct MochiFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.cat", provider: FamilyProvider()) { entry in
            FamilyBody { MochiFamilyView(entry: entry, family: $0) }.familyGround()
        }
        .configurationDisplayName("Mochi")
        .description(CatProfile.pronouns().say(.widgetBlurb))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct UsFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.us", provider: FamilyProvider()) { entry in
            FamilyBody { UsFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.calendar.url)
        }
        .configurationDisplayName("Days together")
        .description("Your days together, the next date and the streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct PartnerFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.partner", provider: FamilyProvider()) { entry in
            FamilyBody { PartnerFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.inbox.url)
        }
        .configurationDisplayName("From your partner")
        .description("Their latest drawing or mood, with a tap to reply.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct CoinsFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.coins", provider: FamilyProvider()) { entry in
            FamilyBody { CoinsFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.room.url)
        }
        .configurationDisplayName("Coins")
        .description("Your coins and how far Mochi's care has come.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

struct MemoryFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.memory", provider: FamilyProvider(loadsPhoto: true)) { entry in
            FamilyBody { MemoryFamilyView(entry: entry, family: $0) }.familyGround().widgetURL(DeepLink.moments.url)
        }
        .configurationDisplayName("Memory")
        .description("A pinned moment, printed like a photo.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

/// Large: Mochi over the two things that matter most, days together and the partner.
struct DayFamilyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ourio.app.day", provider: FamilyProvider()) { entry in
            FamilyBody { DayFamilyView(entry: entry, family: $0) }.familyGround()
        }
        .configurationDisplayName("Our day")
        .description("Mochi, your days together and your partner, in one.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

/// Hands the widget's family to a view that takes it as a parameter, so a bigger widget can lay a smaller one out.
struct FamilyBody<Content: View>: View {
    let content: (WidgetFamily) -> Content
    @Environment(\.widgetFamily) private var family

    init(@ViewBuilder content: @escaping (WidgetFamily) -> Content) { self.content = content }

    var body: some View { content(family) }
}

