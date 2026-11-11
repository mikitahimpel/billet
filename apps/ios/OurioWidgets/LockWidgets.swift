import Design
import MoodInterface
import OurioShared
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

private extension View {
    func lockGround() -> some View {
        containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }
}

extension PartnerMood {
    /// A plain glyph for the Lock Screen, where the clay faces would turn into a flat blob.
    var lockSymbol: String {
        switch self {
        case .happy: "face.smiling"
        case .sleepy: "moon.zzz.fill"
        case .missing: "heart.fill"
        case .busy: "book.fill"
        }
    }
}

extension MochiPose {
    var lockSymbol: String {
        switch self {
        case .purring: "heart.fill"
        case .asleep: "moon.zzz.fill"
        case .waiting: "envelope.fill"
        case .chirpy: "music.note"
        case .napping: "zzz"
        case .quiet: "ellipsis.bubble.fill"
        case .idle: "pawprint.fill"
        }
    }
}

// MARK: - Us

struct UsLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label {
                if let next = s.next { Text("\(s.daysTogether) days · \(next.title) \(next.daysLeft == 0 ? "today" : "in \(next.daysLeft)d")") }
                else { Text("\(s.daysTogether) days together") }
            } icon: { Image(systemName: "heart.fill") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label("Day \(s.daysTogether)", systemImage: "heart.fill")
                    .font(.ourioHeadline)
                    .widgetAccentable()
                if let next = s.next {
                    Text(next.title).font(.ourioCaption).lineLimit(1)
                    Text(next.daysLeft == 0 ? "Today" : "in \(next.daysLeft) \(next.daysLeft == 1 ? "day" : "days")")
                        .font(.ourioCaption).foregroundStyle(.secondary)
                } else {
                    Text("together").font(.ourioCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(spacing: 0) {
                Image(systemName: "heart.fill").font(.ourioMicro)
                Text("\(s.daysTogether)").font(.ourioTitle).monospacedDigit().minimumScaleFactor(0.5).widgetAccentable()
                Text("days").font(.ourioMicro)
            }
        }
    }
}

// MARK: - Streak

struct StreakLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var glance: StreakGlance { StreakGlance(entry.facts.streak, on: entry.snapshot.date) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Streak \(glance.count) · \(glance.caption)", systemImage: "flame.fill")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: Space.xs) {
                Label(glance.count > 0 ? "Streak \(glance.count)" : "No streak", systemImage: "flame.fill")
                    .font(.ourioHeadline)
                    .widgetAccentable()
                Text(glance.caption).font(.ourioCaption).foregroundStyle(.secondary).lineLimit(1)
                Gauge(value: glance.progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Gauge(value: glance.progress) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(glance.count)").monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }
}

// MARK: - Mochi

struct CatLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }
    private var pose: MochiPose { MochiPose.pose(s, drawing: entry.facts.drawing) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(s.catName) · \(pose.word)", systemImage: pose.lockSymbol)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label("\(s.catName) · \(pose.word)", systemImage: pose.lockSymbol)
                    .font(.ourioHeadline)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(pose.line(s, drawing: entry.facts.drawing)).font(.ourioCaption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Image(systemName: pose.lockSymbol)
                .font(.ourioTitle)
                .widgetAccentable()
                .accessibilityLabel("\(s.catName), \(pose.word.lowercased())")
        }
    }
}

// MARK: - Partner

struct PartnerLockView: View {
    let entry: FamilyEntry
    let family: WidgetFamily
    private var s: OurioSnapshot { entry.snapshot }
    private var news: PartnerNews? { PartnerNews.latest(s, drawing: entry.facts.drawing) }

    private var symbol: String {
        switch news {
        case .drawing: "scribble.variable"
        case .mood(let check): check.mood.lockSymbol
        case nil: "ellipsis"
        }
    }

    private var words: String {
        switch news {
        case .drawing: "drew you something"
        case .mood(let check): check.mood.title
        case nil: "Nothing yet"
        }
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(s.partner) · \(words)", systemImage: symbol).privacySensitive()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label(s.partner, systemImage: symbol).font(.ourioHeadline).widgetAccentable()
                Text(words).font(.ourioCaption).lineLimit(1)
                if let news {
                    Text("\(Text(news.date, style: .relative)) ago").font(.ourioCaption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .privacySensitive()
        default:
            Image(systemName: symbol)
                .font(.ourioTitle)
                .widgetAccentable()
                .privacySensitive()
                .accessibilityLabel("\(s.partner), \(words)")
        }
    }
}
